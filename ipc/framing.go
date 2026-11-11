package ipc

import (
	"bufio"
	"io"
)

// maxIPCFrameSize bounds every incoming NDJSON request frame on the server.
const maxIPCFrameSize = 1 << 20

// maxResponseFrameSize bounds NDJSON response frames read by IPC clients so
// track batches carrying embedded metadata or lyrics do not overflow bufio.Scanner.
const maxResponseFrameSize = 4 << 20

func newFrameScanner(reader io.Reader) *bufio.Scanner {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 64*1024), maxIPCFrameSize)
	return scanner
}

func newResponseFrameScanner(reader io.Reader) *bufio.Scanner {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 64*1024), maxResponseFrameSize)
	return scanner
}
