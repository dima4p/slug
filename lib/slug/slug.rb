module Slug
  module ClassMethods
    
    # Call this to set up slug handling on an ActiveRecord model.
    #
    # Params:
    # * <tt>:source</tt> - the column the slug will be based on (e.g. :<tt>headline</tt>)
    #
    # Options:
    # * <tt>:column</tt> - the column the slug will be saved to (defaults to <tt>:slug</tt>)
    #
    # Slug will take care of validating presence and uniqueness of slug. It will generate the slug before create;
    # subsequent changes to the source column will have no effect on the slug.  If you'd like to update the slug
    # later on, call <tt>@model.set_slug</tt>
    def slug source, opts={}
      class_inheritable_accessor :slug_source, :slug_column
      
      self.slug_source = source
      raise ArgumentError, "Source column '#{self.slug_source}' does not exist!" if !self.column_names.include?(self.slug_source.to_s)
      
      self.slug_column = opts.has_key?(:column) ? opts[:column] : :slug
      raise ArgumentError, "Slug column '#{self.slug_column}' does not exist! #{self.column_names.join(',')}" if !self.column_names.include?(self.slug_column.to_s)
      
      validates_presence_of self.slug_column
      validates_uniqueness_of self.slug_column
      before_validation_on_create :set_slug 
    end
  end
  
  # Sets the slug. Called before create.
  def set_slug
    self[self.slug_column] = self[self.slug_source]

    strip_diacritics_from_slug
    normalize_slug
    assign_slug_sequence
    
    self.errors.add(self.slug_column, "#{self.slug_column} cannot be blank. Is #{self.slug_source} sluggable?") if self[self.slug_column].blank?
  end
  
  # Overrides to_param to return the model's slug.
  def to_param
    self[self.slug_column]
  end
  
  def self.included(klass)
    klass.extend(ClassMethods)
  end
  
  private
  # Takes the slug, downcases it and replaces non-word characters with a -.
  # Feel free to override this method if you'd like different slug formatting.
  def normalize_slug
    return if self[self.slug_column].blank?
    s = ActiveSupport::Multibyte.proxy_class.new(self[self.slug_column]).normalize(:kc)
    s.downcase!
    s.strip!
    s.gsub!(/[\W]/u, ' ') # Remove non-word characters
    s.gsub!(/\s+/u, '-') # Convert whitespaces to dashes
    s.gsub!(/-\z/u, '') # Remove trailing dashes
    self[self.slug_column] = s.to_s
  end
  
  # Converts accented characters to their ASCII equivalents and removes them if they have no equivalent.
  # Override this with a void function if you don't want accented characters to be stripped.
  def strip_diacritics_from_slug
    return if self[self.slug_column].blank?
    s = ActiveSupport::Multibyte.proxy_class.new(self[self.slug_column])
    s = s.normalize(:kd).unpack('U*')
    s = s.inject([]) do |a,u|
      if Slug::ASCII_APPROXIMATIONS[u]
        a += Slug::ASCII_APPROXIMATIONS[u].unpack('U*')
      elsif (u < 0x300 || u > 0x036F)
        a << u
      end
      a
    end
    s = s.pack('U*')
    s.gsub!(/[^a-z0-9]+/i, ' ')
    self[self.slug_column] = s.to_s
  end
  
  # If a slug of the same name already exists, this will append '-n' to the end of the slug to
  # make it unique. The second instance gets a '-1' suffix.
  def assign_slug_sequence
    return if self[self.slug_column].blank?
    idx = next_slug_sequence
    self[self.slug_column] = "#{self[self.slug_column]}-#{idx}" if idx > 0
  end
  
  # Returns the next unique index for a slug.
  def next_slug_sequence
    last_in_sequence = self.class.find(:first, :conditions => ["#{self.slug_column} LIKE ?", self[self.slug_column] + '%'],
                                         :order => "CAST(REPLACE(#{self.slug_column},'#{self[self.slug_column]}','') AS UNSIGNED)")
    if last_in_sequence.nil?
      return 0
    else
      sequence_match = last_in_sequence[self.slug_column].match(/^#{self[self.slug_column]}(-(\d+))?/)
      current = sequence_match.nil? ? 0 : sequence_match[2].to_i
      return current + 1
    end
  end
  
end