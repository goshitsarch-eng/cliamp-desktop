package main

import (
	"io"
	"strings"
	"testing"
)

func TestFirstLine(t *testing.T) {
	for _, tt := range []struct{ name, in, want string }{
		{"newline", "{\"a\":1}\n", "{\"a\":1}\n"},
		{"ignores rest", "{\"a\":1}\nnext", "{\"a\":1}\n"},
		{"no newline", "{\"a\":1}", "{\"a\":1}"},
		{"empty", "", ""},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, err := io.ReadAll(firstLine(strings.NewReader(tt.in)))
			if err != nil || string(got) != tt.want {
				t.Fatalf("firstLine(%q) = %q, %v; want %q", tt.in, got, err, tt.want)
			}
		})
	}
}
