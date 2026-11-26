// Shared price math for the resource builder and the New app summary.
// Mirrors Billing::Pricing.monthly_idr (units = pricing.unit_prices, IDR/month);
// keep them in sync. Not a Stimulus controller: the lazy loader skips it.
export function monthlyIdr(units, { cpu, memoryMb, diskGb = 0, count = 1 }) {
  return Math.round(count * (cpu * units.cpu + (memoryMb / 1024) * units.memory_gb) + diskGb * units.disk_gb)
}

// Rp30.000 (id) / Rp30,000 (en): the delimiter comes from the locale.
export function formatIdr(n, delimiter = ".") {
  return `Rp${Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, delimiter)}`
}
