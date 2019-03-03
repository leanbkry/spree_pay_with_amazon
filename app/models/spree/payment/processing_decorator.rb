Spree::Payment::Processing.module_eval do
  def close!
    return true unless source.respond_to?(:close!)
    source.close!(self)
  end
end
