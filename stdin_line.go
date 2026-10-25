package main

import (
	"bufio"
	"io"
	"strings"
)

// maxInputLine bounds one JSON request line read from stdin.
const maxInputLine = 16 << 20

// firstLine returns the first line of r, so the JSON subcommands finish when a
// client sends one newline-terminated request without closing stdin. Some
// clients, such as the Godot desktop app, cannot close a child's stdin alone.
// Input with no newline is returned whole, as before.
func firstLine(r io.Reader) io.Reader {
	line, err := bufio.NewReader(io.LimitReader(r, maxInputLine)).ReadString('\n')
	if err != nil && err != io.EOF {
		return errReader{err}
	}
	return strings.NewReader(line)
}

type errReader struct{ err error }

func (e errReader) Read([]byte) (int, error) { return 0, e.err }
