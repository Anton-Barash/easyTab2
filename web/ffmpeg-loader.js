// FFmpeg Loader Script
// Ожидает, что /assets/ffmpeg/ffmpeg.js уже загружен статически в index.html.
(function() {
  console.log('Configuring FFmpeg...');

  if (typeof FFmpegWASM !== 'undefined' && FFmpegWASM.FFmpeg) {
    window.FFmpeg = FFmpegWASM.FFmpeg;

    window.FFmpegConfig = {
      coreURL: window.location.origin + '/assets/ffmpeg/ffmpeg-core.js',
      wasmURL: window.location.origin + '/assets/ffmpeg/ffmpeg-core.wasm',
    };

    console.log('FFmpeg configured with local files:');
    console.log('  Core JS:', window.FFmpegConfig.coreURL);
    console.log('  WASM:', window.FFmpegConfig.wasmURL);

    /**
     * Создать новый экземпляр ffmpeg.wasm.
     */
    window.createFFmpegInstance = function() {
      console.log('Creating FFmpeg instance...');
      return new FFmpegWASM.FFmpeg();
    };

    let sharedFfmpeg = null;
    let loadPromise = null;

    /**
     * Вернуть инициализированный экземпляр ffmpeg.wasm (singleton).
     * Загружает coreURL/wasmURL при первом вызове.
     */
    async function ensureFfmpeg() {
      if (sharedFfmpeg && sharedFfmpeg.loaded) {
        return sharedFfmpeg;
      }
      if (loadPromise) {
        return loadPromise;
      }

      loadPromise = (async () => {
        sharedFfmpeg = window.createFFmpegInstance();
        await sharedFfmpeg.load({
          coreURL: window.FFmpegConfig.coreURL,
          wasmURL: window.FFmpegConfig.wasmURL,
        });
        return sharedFfmpeg;
      })();

      try {
        return await loadPromise;
      } finally {
        loadPromise = null;
      }
    }

    /**
     * Сжать видео в основном потоке через ffmpeg.wasm.
     *
     * В Web Worker UMD-сборка ffmpeg.js падает с "document is not defined",
     * поэтому сжатие выполняется здесь. UI Flutter блокируется на время exec,
     * но пользователь видит модальный диалог с прогрессом.
     *
     * @param {Uint8Array} bytes — исходное видео
     * @param {object} config — { crf, width, height, fps }
     * @param {function(number): void} onProgress — callback прогресса 0..1
     * @returns {Promise<Uint8Array>}
     */
    window.compressVideoInWorker = async function(bytes, config, onProgress) {
      const inputName = 'input.mp4';
      const outputName = 'output.mp4';

      const crf = config && config.crf != null ? config.crf : 28;
      const width = config && config.width != null ? config.width : -1;
      const height = config && config.height != null ? config.height : 720;
      const fps = config && config.fps != null ? config.fps : 24;

      const ffmpeg = await ensureFfmpeg();

      ffmpeg.on('progress', (event) => {
        if (typeof onProgress === 'function' && event && typeof event.progress === 'number') {
          onProgress(Math.max(0, Math.min(1, event.progress)));
        }
      });

      await ffmpeg.writeFile(inputName, bytes);

      const scaleFilter =
        width > 0 && height > 0
          ? `scale=${width}:${height}:force_original_aspect_ratio=decrease`
          : `scale=-2:${height}`;

      const args = [
        '-i', inputName,
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-crf', String(crf),
        '-vf', scaleFilter,
        '-r', String(fps),
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        outputName,
      ];

      await ffmpeg.exec(args);

      const data = await ffmpeg.readFile(outputName);
      const resultBytes = data instanceof Uint8Array ? data : new Uint8Array(data);

      // Очистка виртуальной файловой системы.
      try {
        await ffmpeg.deleteFile(inputName);
        await ffmpeg.deleteFile(outputName);
      } catch (cleanupErr) {
        // Игнорируем ошибки очистки.
      }

      return resultBytes;
    };

    window.dispatchEvent(new Event('ffmpeg-ready'));
    console.log('FFmpeg ready');
  } else {
    console.error('FFmpegWASM not found');
  }
})();
