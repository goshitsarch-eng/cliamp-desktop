package main

import (
	"bufio"
	"io"
	"os"
	"strings"

	"github.com/charmbracelet/x/term"
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

// nonTerminalFirstLine skips reading when r is an interactive terminal so
// read-only schema and list commands do not block waiting for Enter.
func nonTerminalFirstLine(r io.Reader) io.Reader {
	if r == nil {
		return nil
	}
	if f, ok := r.(*os.File); ok && term.IsTerminal(f.Fd()) {
		return nil
	}
	return firstLine(r)
}

type errReader struct{ err error }

func (e errReader) Read([]byte) (int, error) { return 0, e.err }
