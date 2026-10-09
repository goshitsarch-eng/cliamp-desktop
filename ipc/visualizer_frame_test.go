package ipc

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestVisualizerFrameMethodRoutesWithoutOperationRegistry(t *testing.T) {
	sock := filepath.Join(shortTempDir(t), "cliamp.sock")
	server, err := NewServer(sock)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	server.SetV2Dispatcher(V2DispatcherFunc(func(_ context.Context, request V2Request) (V2Result, *V2Error) {
		if request.Method != "visualizer.frame" || request.Width != 80 || request.Height != 20 {
			t.Errorf("request = %+v", request)
		}
		return V2Result{Result: json.RawMessage(`{"ok":true,"frame":"test"}`)}, nil
	}))
	response := sendV2Request(t, sock, V2Request{Method: " Visualizer.Frame ", Width: 80, Height: 20})
	if !response.OK || response.Job != nil || len(response.Result) == 0 {
		t.Fatalf("response = %+v", response)
	}
	response = sendV2Request(t, sock, V2Request{Method: "visualizer.frame", Operation: "play"})
	if response.OK || errorCode(response.Error) != V2ErrorCodeInvalidRequest {
		t.Fatalf("invalid frame request = %+v", response)
	}
}
