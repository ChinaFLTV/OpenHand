export interface SaveBlobPickerType {
  description: string;
  accept: Record<string, string[]>;
}

export interface SaveBlobResult {
  filename: string;
  picked: boolean;
}

interface FileSystemWritableFileStream {
  write(data: Blob): Promise<void>;
  close(): Promise<void>;
}

interface FileSystemFileHandle {
  createWritable(): Promise<FileSystemWritableFileStream>;
}

interface SaveFilePickerOptions {
  suggestedName?: string;
  types?: SaveBlobPickerType[];
}

type SaveFilePicker = (options?: SaveFilePickerOptions) => Promise<FileSystemFileHandle>;

function fallbackDownload(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  try {
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    window.setTimeout(() => URL.revokeObjectURL(url), 5000);
  }
}

export async function saveBlobWithPicker(
  blob: Blob,
  filename: string,
  types?: SaveBlobPickerType[],
): Promise<SaveBlobResult> {
  const suggestedName = filename.trim() || 'download';
  const picker = (window as Window & { showSaveFilePicker?: SaveFilePicker }).showSaveFilePicker;
  if (picker) {
    try {
      const handle = await picker({ suggestedName, types });
      const writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      return { filename: suggestedName, picked: true };
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        throw error;
      }
    }
  }
  fallbackDownload(blob, suggestedName);
  return { filename: suggestedName, picked: false };
}
