package services

import (
	"context"
	"fmt"
	"strconv"
	"strings"
)

// runRabbitAdmin execs rabbitmqctl inside the shared parent container.
// rabbitmqctl authenticates to the local node via the Erlang cookie inside
// the container — no AMQP password needed (dokku-shared-rabbitmq's
// run_rabbitmq_admin).
func runRabbitAdmin(ctx context.Context, x execer, container string, args ...string) (string, error) {
	return x.Exec(ctx, container, "", append([]string{"rabbitmqctl"}, args...)...)
}

func rabbitAlreadyExistsErr(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "already exists") || strings.Contains(msg, "already_exists")
}

func rabbitNotFoundErr(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "no_such") || strings.Contains(msg, "not found") || strings.Contains(msg, "not_found")
}

// rabbitProvisionTenant creates vhost + user + permissions, translated from
// the plugin's service_create: full configure/write/read WITHIN the vhost,
// nothing outside it. An existing vhost alone is tolerated (a half-finished
// earlier provision may have left it); an existing USER is the real
// tenant_exists signal — that's the credential step. QuotaMB/MaxConns are
// accepted per the op params contract but unused here.
func rabbitProvisionTenant(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
	if !validSlug(p.Slug) {
		return nil, fmt.Errorf("invalid tenant slug: %q", p.Slug)
	}
	if _, err := runRabbitAdmin(ctx, x, container, "add_vhost", p.Slug); err != nil && !rabbitAlreadyExistsErr(err) {
		return nil, fmt.Errorf("add vhost: %w", err)
	}
	if _, err := runRabbitAdmin(ctx, x, container, "add_user", p.Slug, p.Password); err != nil {
		if rabbitAlreadyExistsErr(err) {
			return nil, fmt.Errorf("tenant %q: %w", p.Slug, errTenantExists)
		}
		return nil, fmt.Errorf("add user: %w", err)
	}
	if _, err := runRabbitAdmin(ctx, x, container, "set_permissions", "-p", p.Slug, p.Slug, ".*", ".*", ".*"); err != nil {
		return nil, fmt.Errorf("set permissions: %w", err)
	}
	return map[string]string{"slug": p.Slug, "user": p.Slug, "vhost": p.Slug}, nil
}

// rabbitDestroyTenant deletes the tenant user and vhost (delete_vhost drops
// every queue, exchange, binding, and message in it). Already-gone state is
// tolerated per entity — the plugin `|| true`'d both, we tolerate only
// not-found errors so a broken broker still fails loud.
func rabbitDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}
	if _, err := runRabbitAdmin(ctx, x, container, "delete_user", slug); err != nil && !rabbitNotFoundErr(err) {
		return fmt.Errorf("delete user: %w", err)
	}
	if _, err := runRabbitAdmin(ctx, x, container, "delete_vhost", slug); err != nil && !rabbitNotFoundErr(err) {
		return fmt.Errorf("delete vhost: %w", err)
	}
	return nil
}

// rabbitCheckQuotas sums messages across all queues in each tenant's vhost
// (plugin's tenant_usage awk) and applies the write-permission flip in the
// same pass, unconditionally like pgCheckQuotas: over -> write regex "",
// under -> ".*" (configure/read kept both ways). Contract note: for this
// engine cap_bytes carries the MESSAGE cap, and size_bytes reports the
// message count — the quota unit is messages, not bytes.
func rabbitCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		if !validSlug(t.Slug) {
			return nil, fmt.Errorf("invalid tenant slug: %q", t.Slug)
		}
		out, err := runRabbitAdmin(ctx, x, container, "list_queues", "-p", t.Slug, "messages", "-q")
		if err != nil {
			return nil, fmt.Errorf("list queues %q: %w", t.Slug, err)
		}
		// Numeric-last-field filter, robust to header/quiet-mode differences
		// across RabbitMQ versions (plugin's awk).
		var msgs int64
		for _, line := range strings.Split(out, "\n") {
			fields := strings.Fields(line)
			if len(fields) == 0 {
				continue
			}
			if n, perr := strconv.ParseInt(fields[len(fields)-1], 10, 64); perr == nil {
				msgs += n
			}
		}

		over := msgs > t.CapBytes
		write := ".*"
		if over {
			write = ""
		}
		if _, err := runRabbitAdmin(ctx, x, container, "set_permissions", "-p", t.Slug, t.Slug, ".*", write, ".*"); err != nil {
			return nil, fmt.Errorf("quota flip %q: %w", t.Slug, err)
		}

		statuses = append(statuses, TenantQuotaStatus{
			Slug:      t.Slug,
			SizeBytes: msgs,
			CapBytes:  t.CapBytes,
			Over:      over,
			ReadOnly:  over,
		})
	}
	return statuses, nil
}
