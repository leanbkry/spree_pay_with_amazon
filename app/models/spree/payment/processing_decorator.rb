module Spree::Payment::ProcessingDecorator
  def self.close!
    return true unless source.respond_to?(:close!)
    source.close!(self)
  end
end

::Spree::Payment::Processing.prepend(Spree::Payment::ProcessingDecorator)