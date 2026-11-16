package vitals

import "testing"

func TestParseDockerStats(t *testing.T) {
	out := "wokku-audit-astro4-web.1.mjqoo9ckgra1364k8jnxp3jgs\t1.50%\t45.2MiB / 256MiB\n" +
		"wokku-shop-web.1.aaa\t10.00%\t1.5GiB / 2GiB\n" +
		"wokku-shop-web.2.bbb\t5.00%\t512MiB / 2GiB\n" +
		"dokku.postgres.auditpg\t0.3%\t40MiB / 512MiB\n" + // not an app task
		"garbage line\n"
	got := ParseDockerStats(out)

	a, ok := got["wokku-audit-astro4-web"]
	if !ok || a.CPUPct != 1.5 || a.MemMB != 45 || a.MemLimitMB != 256 {
		t.Fatalf("astro: %+v ok=%v", a, ok)
	}
	// Replicas of one service add up; the limit is per container, so keep it.
	s := got["wokku-shop-web"]
	if s.CPUPct != 15 || s.MemMB != 2048 || s.MemLimitMB != 2048 {
		t.Fatalf("shop: %+v", s)
	}
	if _, ok := got["dokku.postgres.auditpg"]; ok || len(got) != 2 {
		t.Fatalf("unexpected keys: %v", got)
	}
}
