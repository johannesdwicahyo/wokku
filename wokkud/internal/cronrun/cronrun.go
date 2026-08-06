// Package cronrun executes scheduled tasks as one-off containers (Track B
// B3). Declarative sync: Apply swaps the whole schedule; fire-time env
// fetch; overlap skip; batch typed reports. Fail-static: every failure is
// reported (as a Run row or a log line), never returned up to crash the
// agent.
package cronrun

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/robfig/cron/v3"
)

// newCron builds a cron.Cron with the Recover chain applied — cron.New()'s
// default chain does NOT recover panics despite the package doc's wording;
// only cron.New(cron.WithChain(cron.Recover(...))) does. This is
// belt-and-suspenders defense for anything panicking outside fire() (fire
// itself has its own recover, below); it protects any future direct
// AddFunc/AddJob caller too.
func newCron() *cron.Cron {
	return cron.New(cron.WithChain(cron.Recover(cron.DefaultLogger)))
}

type Config struct {
	Version string  `json:"version"`
	Entries []Entry `json:"entries"`
}

type Entry struct {
	ID             string   `json:"id"`
	App            string   `json:"app"`
	Schedule       string   `json:"schedule"`
	Command        string   `json:"command"`
	TimeoutSeconds int      `json:"timeout_seconds"`
	ImageRef       string   `json:"image_ref"`
	Networks       []string `json:"networks"`
}

type Run struct {
	TaskID        string     `json:"task_id"`
	StartedAt     time.Time  `json:"started_at"`
	FinishedAt    *time.Time `json:"finished_at,omitempty"`
	ExitCode      *int       `json:"exit_code,omitempty"`
	SkippedReason string     `json:"skipped_reason,omitempty"`
	LogExcerpt    string     `json:"log_excerpt,omitempty"`
}

// controlAPI is the narrow slice of control.Client the scheduler needs —
// same narrow-interface trick as dockermon.api and router.configFetcher.
// cronrun defines the wire types (Config/Entry/Run); control.Client
// satisfies this interface structurally, so control can import cronrun for
// the types without cronrun ever importing control back.
type controlAPI interface {
	GetCronConfig() (*Config, error)
	GetAppEnv(app string) (map[string]string, error)
	PostCronRuns([]Run) error
}

// Runner executes one entry to completion. Satisfied by DockerRunner;
// faked in tests (same narrow-interface trick as dockermon.api).
type Runner interface {
	Run(e Entry, env map[string]string) (exitCode int, output string)
}

type Scheduler struct {
	api    controlAPI
	runner Runner

	mu       sync.Mutex
	cron     *cron.Cron
	version  string
	inFlight map[string]bool
}

func NewScheduler(api controlAPI, runner Runner) *Scheduler {
	return &Scheduler{api: api, runner: runner, cron: newCron(), inFlight: map[string]bool{}}
}

func (s *Scheduler) AppliedVersion() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.version
}

// Sync is called from the heartbeat loop when the response version differs
// from AppliedVersion: fetch + Apply. Errors are logged, never fatal.
func (s *Scheduler) Sync() {
	cfg, err := s.api.GetCronConfig()
	if err != nil {
		log.Printf("cronrun: config fetch failed: %v", err)
		return
	}
	if err := s.Apply(cfg); err != nil {
		log.Printf("cronrun: apply failed: %v", err)
	}
}

// Apply atomically swaps the schedule. A config with any invalid schedule
// is rejected whole — the old schedule keeps running (fail-static). A nil
// config is treated as an empty one (clears schedules) rather than a
// nil-deref panic on cfg.Entries.
func (s *Scheduler) Apply(cfg *Config) error {
	if cfg == nil {
		cfg = &Config{}
	}
	next := newCron()
	for _, e := range cfg.Entries {
		entry := e // capture
		if _, err := next.AddFunc(e.Schedule, func() { s.fire(entry) }); err != nil {
			return err
		}
	}
	s.mu.Lock()
	old := s.cron
	s.cron = next
	s.version = cfg.Version
	s.mu.Unlock()
	next.Start()
	if old != nil {
		old.Stop()
	}
	return nil
}

func (s *Scheduler) fire(e Entry) {
	started := time.Now().UTC()
	defer func() {
		if r := recover(); r != nil {
			log.Printf("cronrun: task %s panicked: %v", e.ID, r)
			finished := time.Now().UTC()
			code := 1
			s.report(Run{TaskID: e.ID, StartedAt: started, FinishedAt: &finished, ExitCode: &code,
				LogExcerpt: tail(fmt.Sprintf("panic: %v", r), 16384)})
		}
	}()

	s.mu.Lock()
	if s.inFlight[e.ID] {
		s.mu.Unlock()
		s.report(Run{TaskID: e.ID, StartedAt: time.Now().UTC(), SkippedReason: "overlap"})
		return
	}
	s.inFlight[e.ID] = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.inFlight, e.ID)
		s.mu.Unlock()
	}()

	env, err := s.api.GetAppEnv(e.App)
	if err != nil {
		s.report(Run{TaskID: e.ID, StartedAt: started, SkippedReason: "env_fetch_failed"})
		return
	}
	code, out := s.runner.Run(e, env)
	finished := time.Now().UTC()
	s.report(Run{TaskID: e.ID, StartedAt: started, FinishedAt: &finished, ExitCode: &code,
		LogExcerpt: tail(out, 16384)})
}

func (s *Scheduler) report(r Run) {
	if err := s.api.PostCronRuns([]Run{r}); err != nil {
		log.Printf("cronrun: report failed for task %s: %v", r.TaskID, err)
	}
}

func tail(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:]
}
