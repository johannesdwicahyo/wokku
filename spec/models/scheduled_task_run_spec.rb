require "rails_helper"

RSpec.describe ScheduledTaskRun do
  it "trims log_excerpt to 16KB on save" do
    run = create(:scheduled_task_run, log_excerpt: "x" * 20_000)
    expect(run.log_excerpt.bytesize).to eq(16_384)
  end

  it "scrubs a multibyte char split by the 16KB byteslice boundary so the row still saves" do
    # "€" is 3 bytes; char 5461 occupies bytes [16383, 16385], so slicing at
    # byte 16384 cuts it mid-sequence and leaves an invalid trailing byte.
    excerpt = "€" * 9_000
    run = create(:scheduled_task_run, log_excerpt: excerpt)

    expect(run).to be_persisted
    expect(run.log_excerpt.valid_encoding?).to be true
  end
end
