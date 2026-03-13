class ServerPlacement
  def initialize(team:, required_memory_mb:, region: nil)
    @team = team
    @required_memory_mb = required_memory_mb
    @region = region
  end

  def find_best_server
    servers = @team.servers.where(status: :connected)
    servers = servers.where(region: @region) if @region.present?

    best = servers
      .where("capacity_total_mb - capacity_used_mb >= ?", @required_memory_mb)
      .order(Arel.sql("capacity_total_mb - capacity_used_mb DESC"))
      .first

    best || raise(NoCapacityError, "No server with enough capacity (#{@required_memory_mb}MB needed)")
  end

  class NoCapacityError < StandardError; end
end
