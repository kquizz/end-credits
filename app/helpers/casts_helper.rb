module CastsHelper
  # The cast pages serve two tools; routes are named cast_* (EGOTs) and ages_* (ages).
  def ages? = params[:tool] == "ages"
  def tool_key = ages? ? "ages" : "egot"
  def tool_entry = Tool.all.find { |t| t.slug == (ages? ? "ages" : "cast") }

  def tool_path(kind = nil, *args, **opts)
    public_send("#{[ ages? ? 'ages' : 'cast', kind ].compact.join('_')}_path", *args, **opts)
  end

  def long_date(date) = date&.strftime("%B %-d, %Y")
end
