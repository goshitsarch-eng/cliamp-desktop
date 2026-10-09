package model

import (
	"encoding/json"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"testing"
)

func TestDesktopTrackRoundTripKeepsEmbeddedLyrics(t *testing.T) {
	original := playlist.Track{Path: "/music/local.flac", EmbeddedLyrics: "[00:01.25]A tagged lyric", AlbumArtURL: "file:///art.jpg", ProviderMeta: map[string]string{"local.source": "collection"}}
	info := ipcTrackInfo(original, 0, 0, false)
	encoded, err := json.Marshal(info)
	if err != nil {
		t.Fatal(err)
	}
	var decoded ipc.TrackInfo
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	track := ipcTrackFromInfo(decoded)
	if track.EmbeddedLyrics != original.EmbeddedLyrics || track.AlbumArtURL != original.AlbumArtURL || track.Meta("local.source") != "collection" {
		t.Fatalf("metadata lost: %+v", track)
	}
}

func TestDesktopLyricsOffsetReadResetAndBounds(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{}, nil)
	saver := &recordingSaver{}
	m.configSaver = saver
	m.SetLyricsOffset(750)
	for _, tc := range []struct {
		raw   string
		want  int64
		valid bool
	}{
		{`{}`, 750, true}, {`{"value":250}`, 250, true}, {`{"value":0}`, 0, true},
		{`{"value":-10000}`, -10000, true}, {`{"value":10000}`, 10000, true},
		{`{"value":10001}`, 10000, false}, {`{"value":0.5}`, 10000, false},
	} {
		msg := v2Request(t, "lyrics.offset", ipc.Request{})
		msg.Request.Params = json.RawMessage(tc.raw)
		next, _ := m.Update(msg)
		m = next.(Model)
		job, _ := msg.Jobs.Get(msg.JobID)
		if (job.State == ipc.JobSucceeded) != tc.valid {
			t.Fatalf("%s: state=%s error=%+v", tc.raw, job.State, job.Error)
		}
		if m.runtimeSnapshot().LyricsOffsetMS != tc.want {
			t.Fatalf("%s: got %d want %d", tc.raw, m.runtimeSnapshot().LyricsOffsetMS, tc.want)
		}
	}
	if saver.saved["lyrics_offset_ms"] != "10000" {
		t.Fatalf("saved: %v", saver.saved)
	}
}
