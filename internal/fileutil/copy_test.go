package fileutil

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.txt")
	dst := filepath.Join(dir, "dst.txt")

	content := []byte("hello world")
	if err := os.WriteFile(src, content, 0o644); err != nil {
		t.Fatal(err)
	}

	if err := CopyFile(src, dst); err != nil {
		t.Fatalf("CopyFile: %v", err)
	}

	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("reading dst: %v", err)
	}
	if string(got) != string(content) {
		t.Fatalf("got %q, want %q", got, content)
	}
}

func TestCopyFileMissingSrc(t *testing.T) {
	dir := t.TempDir()
	err := CopyFile(filepath.Join(dir, "nonexistent"), filepath.Join(dir, "dst"))
	if err == nil {
		t.Fatal("expected error for missing source")
	}
}

func TestCopyFileOverwrite(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.txt")
	dst := filepath.Join(dir, "dst.txt")

	os.WriteFile(src, []byte("new"), 0o644)
	os.WriteFile(dst, []byte("old"), 0o644)

	if err := CopyFile(src, dst); err != nil {
		t.Fatalf("CopyFile: %v", err)
	}

	got, _ := os.ReadFile(dst)
	if string(got) != "new" {
		t.Fatalf("got %q, want %q", got, "new")
	}
}

func TestCopyFileEmptyFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "empty.txt")
	dst := filepath.Join(dir, "dst.txt")

	os.WriteFile(src, []byte{}, 0o644)

	if err := CopyFile(src, dst); err != nil {
		t.Fatalf("CopyFile: %v", err)
	}

	got, _ := os.ReadFile(dst)
	if len(got) != 0 {
		t.Fatalf("expected empty file, got %d bytes", len(got))
	}
}

func TestCopyFileSameRecording(t *testing.T) {
	for _, alias := range []bool{false, true} {
		name := "same path"
		if alias {
			name = "hard link"
		}
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			src := filepath.Join(dir, "audio.wav")
			want := "recorded audio"
			if err := os.WriteFile(src, []byte(want), 0o600); err != nil {
				t.Fatal(err)
			}
			dst := src
			if alias {
				dst = filepath.Join(dir, "second.wav")
				if err := os.Link(src, dst); err != nil {
					t.Skipf("hard links unavailable: %v", err)
				}
			}
			if err := CopyFile(src, dst); err != nil {
				t.Fatal(err)
			}
			got, err := os.ReadFile(src)
			if err != nil || string(got) != want {
				t.Fatalf("original after repeat save = %q, error %v", got, err)
			}
		})
	}
}
