// FFmpeg Loader Script
// Ленивая загрузка ffmpeg.wasm: тяжёлая UMD-сборка /assets/ffmpeg/ffmpeg.js
// подгружается динамически ТОЛЬКО при первом сжатии видео, чтобы не
// блокировать стартовую страницу приложения (быстрая загрузка UI).
(function() {
  'use strict';

  let ffmpegScriptPromise = null;
  let sharedFfmpeg = null;
  let loadPromise = null;
  let ffmpegConfigured = false;

  const CORE_URL = window.location.origin + '/assets/ffmpeg/ffmpeg-core.js';
  const WASM_URL = window.location.origin + '/assets/ffmpeg/ffmpeg-core.wasm';

  /**
   * Динамически загрузить /assets/ffmpeg/ffmpeg.js (UMD-сборка ffmpeg.wasm)
   * и настроить глобальные ссылки. Вызывается только при первом сжатии.
   */
  function loadFfmpegScript() {
    if (ffmpegScriptPromise) return ffmpegScriptPromise;

    // Уже загружен статически (на случай, если ffmpeg.js снова подключат в index.html).
    if (typeof FFmpegWASM !== 'undefined' && FFmpegWASM.FFmpeg) {
      configureFfmpeg();
      return Promise.resolve();
    }

    ffmpegScriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = window.location.origin + '/assets/ffmpeg/ffmpeg.js';
      script.async = true;
      script.onload = () => {
        if (typeof FFmpegWASM === 'undefined' || !FFmpegWASM.FFmpeg) {
          reject(new Error('ffmpeg.js loaded, but FFmpegWASM not found'));
          return;
        }
        configureFfmpeg();
        resolve();
      };
      script.onerror = () => {
        ffmpegScriptPromise = null;
        reject(new Error('Failed to load /assets/ffmpeg/ffmpeg.js'));
      };
      document.head.appendChild(script);
    });

    return ffmpegScriptPromise;
  }

  /**
   * Настроить глобальные ссылки FFmpeg (один раз).
   */
  function configureFfmpeg() {
    if (ffmpegConfigured) return;
    ffmpegConfigured = true;

    window.FFmpeg = FFmpegWASM.FFmpeg;
    window.FFmpegConfig = {
      coreURL: CORE_URL,
      wasmURL: WASM_URL,
    };

    /**
     * Создать новый экземпляр ffmpeg.wasm.
     */
    window.createFFmpegInstance = function() {
      return new FFmpegWASM.FFmpeg();
    };

    console.log('FFmpeg configured with local files:', window.FFmpegConfig);
  }

  /**
   * Вернуть инициализированный экземпляр ffmpeg.wasm (singleton).
   * Загружает ffmpeg.js + coreURL/wasmURL при первом вызове.
   */
  async function ensureFfmpeg() {
    if (sharedFfmpeg && sharedFfmpeg.loaded) {
      return sharedFfmpeg;
    }
    if (loadPromise) {
      return loadPromise;
    }

    loadPromise = (async () => {
      await loadFfmpegScript();
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

    // P3-56: сохраняем размер ДО передачи в FFmpeg.
    // ffmpeg.writeFile() transfer'ит ArrayBuffer — после вызова bytes.length может стать 0.
    const originalSize = bytes.length;

    // Проверка исходного размера
    if (originalSize === 0) {
      throw new Error('Исходный файл пустой (0 байт). Невозможно сжать.');
    }

    // P3-56: передаём копию bytes в writeFile, т.к. он может transfer'ить буфер
    await ffmpeg.writeFile(inputName, new Uint8Array(bytes));

    // P3-56: force_divisible_by=2 обязателен! Без него libx264 падает
    // с "width not divisible by 2" на видео с нечётными размерами
    // (например 592x1280 → scale даёт 333x720 → 333 нечётное → Conversion failed! → 0 байт).
    const scaleFilter =
      width > 0 && height > 0
        ? `scale=${width}:${height}:force_original_aspect_ratio=decrease:force_divisible_by=2`
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

    // Проверка на пустой результат
    if (resultBytes.length === 0) {
      throw new Error('Результат сжатия пустой (0 байт). FFmpeg не смог обработать файл.');
    }

    // Очистка виртуальной файловой системы.
    try {
      await ffmpeg.deleteFile(inputName);
      await ffmpeg.deleteFile(outputName);
    } catch (cleanupErr) {
      // Игнорируем ошибки очистки.
    }

    return resultBytes;
  };

  /**
   * Проверить, загружен ли ffmpeg.wasm в память.
   * Используется для пропуска диалога-предупреждения о скачивании ~25 МБ.
   */
  window.isFfmpegLoaded = function() {
    return !!(sharedFfmpeg && sharedFfmpeg.loaded);
  };
})();
