class ServerPlacement
  def initialize(team:, required_memory_mb:, region: nil)
    @team = team
    @required_memory_mb = required_memory_mb
    @region = region
  end

  def find_best_server
    servers = @team.servers.where(status: :connected)
    servers = servers.where(region: @region) if @region.present?

    # Free capacity = host RAM minus memory already committed to dyno
    # allocations. allocated_memory_mb is a derived aggregate, so rank in
    # Ruby rather than SQL.
    best = servers
      .select { |s| free_mb(s) >= @required_memory_mb }
      .max_by { |s| free_mb(s) }

    best || raise(NoCapacityError, "No server with enough capacity (#{@required_memory_mb}MB needed)")
  end

  class NoCapacityError < StandardError; end

  private

  def free_mb(server)
    server.capacity_total_mb.to_i - server.allocated_memory_mb
  end
end
