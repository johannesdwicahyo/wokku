# Rupiah with the locale's thousands delimiter: Rp60.000 (id), Rp60,000 (en).
module RupiahHelper
  def idr(n) = "Rp#{n.to_i.to_s.reverse.scan(/\d{1,3}/).join(I18n.t("number.format.delimiter")).reverse}"
end
