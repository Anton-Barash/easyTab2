// Web Worker для сжатия видео через ffmpeg.wasm.
// Выполняется в отдельном потоке, чтобы не блокировать UI основного приложения.
// Кэширует ffmpeg-core.js и ffmpeg-core.wasm в Cache API после первого скачивания.

importScripts('./ffmpeg.js');

const FFMPEG_CACHE_NAME = 'ffmpeg-cache-v1';
const CORE_URL = './ffmpeg-core.js';
const WASM_URL = './ffmpeg-core.wasm';

let ffmpeg = null;
let loadPromise = null;

/**
 * Возвращает Blob URL для ресурса, используя Cache API.
 * При первом вызове скачивает файл и кладёт в кэш.
 * Если кэш недоступен — возвращает исходный URL.
 */
async function getCachedUrl(url) {
  try {
    const cache = await caches.open(FFMPEG_CACHE_NAME);
    let response = await cache.match(url);
    if (!response) {
      console.log('[VideoWorker] downloading', url);
      response = await fetch(url, { credentials: 'same-origin' });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} for ${url}`);
      }
      // Клонируем ответ, т.к. response может быть прочитан только один раз.
      await cache.put(url, response.clone());
    } else {
      console.log('[VideoWorker] using cached', url);
    }
    const blob = await response.blob();
    return URL.createObjectURL(blob);
  } catch (err) {
    console.warn('[VideoWorker] cache failed for', url, err);
    return url;
  }
}

/**
 * Инициализировать ffmpeg.wasm (один раз).
 */
async function ensureFfmpeg() {
  if (ffmpeg && ffmpeg.loaded) {
    return ffmpeg;
  }
  if (loadPromise) {
    return loadPromise;
  }

  loadPromise = (async () => {
    ffmpeg = new FFmpegWASM.FFmpeg();

    ffmpeg.on('progress', (event) => {
      self.postMessage({ type: 'progress', progress: event.progress });
    });

    ffmpeg.on('log', (event) => {
      self.postMessage({ type: 'log', message: event.message });
    });

    const coreBlobUrl = await getCachedUrl(CORE_URL);
    const wasmBlobUrl = await getCachedUrl(WASM_URL);

    await ffmpeg.load({
      coreURL: coreBlobUrl,
      wasmURL: wasmBlobUrl,
    });

    return ffmpeg;
  })();

  try {
    return await loadPromise;
  } finally {
    loadPromise = null;
  }
}

/**
 * Сжать видео.
 * @param {Uint8Array} bytes — исходное видео
 * @param {object} config — { crf, width, height, fps }
 */
async function compressVideo(id, bytes, config) {
  const inputName = 'input.mp4';
  const outputName = 'output.mp4';

  const crf = config.crf != null ? config.crf : 28;
  const width = config.width != null ? config.width : -1;
  const height = config.height != null ? config.height : 720;
  const fps = config.fps != null ? config.fps : 24;

  self.postMessage({ type: 'status', id, status: 'initializing' });
  const ffmpeg = await ensureFfmpeg();

  // P3-56: сохраняем размер ДО передачи в FFmpeg.
  // ffmpeg.writeFile() transfer'ит ArrayBuffer — после вызова bytes.length может стать 0.
  const originalSize = bytes.length;

  // Проверка исходного размера
  if (originalSize === 0) {
    throw new Error('Исходный файл пустой (0 байт). Невозможно сжать.');
  }

  self.postMessage({ type: 'status', id, status: 'writing' });
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

  self.postMessage({ type: 'status', id, status: 'compressing' });
  await ffmpeg.exec(args);

  self.postMessage({ type: 'status', id, status: 'reading' });
  const data = await ffmpeg.readFile(outputName);

  // ffmpeg.readFile возвращает Uint8Array.
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
}

self.onmessage = async (event) => {
  const { id, type, bytes, config } = event.data;
  if (type !== 'compress') {
    return;
  }

  try {
    const result = await compressVideo(id, new Uint8Array(bytes), config || {});
    self.postMessage(
      { type: 'result', id, success: true, bytes: result },
      [result.buffer]
    );
  } catch (err) {
    self.postMessage({
      type: 'result',
      id,
      success: false,
      error: err && err.message ? err.message : String(err),
    });
  }
};
