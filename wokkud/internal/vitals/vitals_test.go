package vitals

import (
	"strings"
	"testing"
)

const meminfoFixture = `MemTotal:        8148728 kB
MemFree:          217012 kB
MemAvailable:    3860224 kB
Buffers:          301460 kB
`

func TestParseMeminfo(t *testing.T) {
	totalMB, usedMB, err := parseMeminfo(strings.NewReader(meminfoFixture))
	if err != nil {
		t.Fatalf("parseMeminfo: %v", err)
	}
	if totalMB != 7957 { // 8148728 kB / 1024
		t.Fatalf("totalMB: got %d", totalMB)
	}
	if usedMB != 4187 { // (8148728 - 3860224) / 1024
		t.Fatalf("usedMB: got %d, expected 4187", usedMB)
	}
}

func TestParseMeminfoMissingFields(t *testing.T) {
	if _, _, err := parseMeminfo(strings.NewReader("Garbage: 1 kB\n")); err == nil {
		t.Fatal("expected error")
	}
}

func TestParseLoadavg(t *testing.T) {
	load1, err := parseLoadavg(strings.NewReader("2.35 1.80 1.42 3/1234 56789\n"))
	if err != nil {
		t.Fatalf("parseLoadavg: %v", err)
	}
	if load1 != 2.35 {
		t.Fatalf("load1: got %v", load1)
	}
}
