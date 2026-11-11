package telegram

import (
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestStreamSourceServesGrowingFile(t *testing.T) {
	dir := t.TempDir()
	file, err := os.OpenFile(filepath.Join(dir, "track.flac"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	source := newStreamSource(file)

	go func() {
		writer := streamWriter{source: source, file: file}
		_, _ = writer.Write([]byte("hello "))
		time.Sleep(50 * time.Millisecond)
		_, _ = writer.Write([]byte("world"))
		writer.finish(nil)
	}()

	data, err := io.ReadAll(source)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if got, want := string(data), "hello world"; got != want {
		t.Fatalf("read %q, want %q", got, want)
	}
}

func TestStreamSourceSeekWithinDownloadedData(t *testing.T) {
	dir := t.TempDir()
	file, err := os.OpenFile(filepath.Join(dir, "track.flac"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	source := newStreamSource(file)
	writer := streamWriter{source: source, file: file}
	if _, err := writer.Write([]byte("0123456789")); err != nil {
		t.Fatal(err)
	}
	writer.finish(nil)

	if _, err := source.Seek(4, io.SeekStart); err != nil {
		t.Fatalf("Seek: %v", err)
	}
	buffer := make([]byte, 3)
	if _, err := io.ReadFull(source, buffer); err != nil {
		t.Fatalf("ReadFull: %v", err)
	}
	if got, want := string(buffer), "456"; got != want {
		t.Fatalf("read %q, want %q", got, want)
	}
}

func TestStreamSourceReportsDownloadError(t *testing.T) {
	dir := t.TempDir()
	file, err := os.OpenFile(filepath.Join(dir, "track.flac"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	source := newStreamSource(file)
	writer := streamWriter{source: source, file: file}
	_, _ = writer.Write([]byte("part"))
	writer.finish(io.ErrUnexpectedEOF)

	if _, err := io.ReadAll(source); err == nil {
		t.Fatal("expected the download error to surface")
	}
}

func TestStreamSourceSeekEndUsesTotalSizeAndRejectsUnbufferedLiveSeek(t *testing.T) {
	dir := t.TempDir()
	file, err := os.OpenFile(filepath.Join(dir, "track.mp3"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	source := newStreamSource(file)
	source.totalSize = 100
	writer := streamWriter{source: source, file: file}
	if _, err := writer.Write([]byte("0123456789")); err != nil {
		t.Fatal(err)
	}
	end, err := source.Seek(0, io.SeekEnd)
	if err != nil {
		t.Fatalf("SeekEnd: %v", err)
	}
	if end != 100 {
		t.Fatalf("SeekEnd = %d, want 100", end)
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		t.Fatalf("SeekStart: %v", err)
	}
	source.setStreaming(true)
	if _, err := source.Seek(50, io.SeekStart); err == nil {
		t.Fatal("expected live seek past buffered data to return error")
	}
}
