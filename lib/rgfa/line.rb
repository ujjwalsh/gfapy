#
# Generic representation of a record of a RGFA file.
#
# @!macro[new] rgfa_line
#   @note
#     This class is usually not meant to be directly initialized by the user;
#     initialize instead one of its child classes, which define the concrete
#     different record types.
#
class RGFA::Line

  # Separator in the string representation of RGFA lines
  SEPARATOR = "\t"

  # List of allowed record_type values and the associated subclasses of
  # {RGFA::Line}.
  #
  # @developer
  #   In case new record types are defined, add them here and define the
  #   corresponding class (in <tt>lib/gfa/line/<downcasetypename>.rb</tt>).
  #   All file in the +line+ subdirectory are automatically required.
  #
  RECORD_TYPES =
    {
      "H" => "RGFA::Line::Header",
      "S" => "RGFA::Line::Segment",
      "L" => "RGFA::Line::Link",
      "C" => "RGFA::Line::Containment",
      "P" => "RGFA::Line::Path"
    }

  # @param rtype [String] the record type string to be validated
  # @param obj [Object] and object to be displayed in case of error
  # @raise if record type is not one of RGFA::Line::RECORD_TYPES
  def self.validate_record_type!(rtype, obj=nil)
    if !RGFA::Line::RECORD_TYPES.has_key?(rtype)
      msg = "Record type unknown: '#{rtype}'"
      msg += " (#{obj.inspect})" if obj
      raise RGFA::Line::UnknownRecordTypeError, msg
    end
  end

  # @!macro rgfa_line
  #
  # @param fields [Array<String>] the content of the line
  #
  # <b> Constants defined by subclasses </b>
  #
  # Subclasses of RGFA::Line _must_ define the following constants:
  # - RECORD_TYPE [String, size 1]
  # - REQFIELD_DEFINITIONS [Array<Array(Symbol,Regex)>]:
  #   <i>(possibly empty)</i>
  #   defines the order of the required fields (Symbol) in the line and their
  #   validators (Regex)
  # - REQFIELD_CAST [Hash{Symbol=>Lambda}]:
  #   <i>(possibly empty)</i>
  #   defines procedures (Lambda) for casting selected required fields
  #   (Symbol) into instances of the corresponding Ruby classes; the
  #   lambda shall take one argument (the field string value) and
  #   return one argument (the Ruby value)
  # - OPTFIELD_TYPES [Hash{Symbol=>String}]:
  #   <i>(possibly empty)</i> defines the predefined optional
  #   fields and their required type (String)
  #
  # @raise [RGFA::Line::RequiredFieldMissingError]
  #   if too less required fields are specified
  # @raise [RGFA::Line::RequiredFieldTypeError]
  #   if the type of a required field does not match the validation regexp
  # @raise [RGFA::Line::CustomOptfieldNameError]
  #   if a non-predefined optional field uses upcase letters
  # @raise [RGFA::Line::DuplicateOptfieldNameError]
  #   if an optional field tag name is used more than once
  # @raise [RGFA::Line::PredefinedOptfieldTypeError]
  #   if the type of a predefined optional field does not
  #   respect the specified type.
  #
  # @return [RGFA::Line]
  def initialize(fields, validate: true)
    raise "This class shall not be directly instantiated; "+
      "use a subclass instead" if self.record_type.nil?
    @fields = fields
    @fieldnames = []
    @validate = validate
    self.class.validate_record_type!(self.record_type) if @validate
    initialize_required_fields
    initialize_optional_fields
    validate_record_type_specific_info! if @validate
  end

  attr_reader :fieldnames

  def record_type
    self.class::RECORD_TYPE
  end

  # @return [Array<Symbol>] name of the required fields
  def required_fieldnames
    @fieldnames[0,n_required_fields]
  end

  # @return [Array<Symbol>] name of the optional fields
  def optional_fieldnames
    @fieldnames.size > n_required_fields ?
      @fieldnames[n_required_fields..-1] : []
  end

  # @return [self.class] deep copy of self (RGFA::Line subclass)
  def clone
    self.class.new(@fields.clone.map{|e|e.clone})
  end

  # @return [String] a string representation of self
  def to_s
    ([self.class::RECORD_TYPE]+@fields).join(RGFA::Line::SEPARATOR)
  end

  # @overload add_optfield(optfield_string)
  #   @param optfield [String] string representation of an optional field
  #     to add to the line
  # @overload add_optfield(optfield_instance)
  #   @param optfield [RGFA::Optfield] an optional field to add to the line
  # @raise [RGFA::Line::DuplicateOptfieldNameError] if the line already
  #   contains an optional field with the same tag name
  # @return [void]
  def add_optfield(optfield)
    if !optfield.respond_to?(:to_rgfa_optfield)
      raise ArgumentError,
        "The argument must be a string representing "+
        "an optional field or an RGFA::Optfield instance"
    end
    optfield = optfield.to_rgfa_optfield(validate: @validate)
    sym = optfield.tag.to_sym
    if optional_fieldnames.include?(sym)
      raise RGFA::Line::DuplicateOptfieldNameError,
        "Optional tag '#{optfield.tag}' exists more than once"
    end
    validate_optional_field!(optfield) if @validate
    @fields << optfield
    @fieldnames << sym
    nil
  end

  # Remove an optional field from the line
  # @param optfield_tag [#to_sym] the tag name of the optfield to remove
  # @return [void]
  def rm_optfield(optfield_tag)
    i = optional_fieldnames.index(optfield_tag.to_sym)
    if !i.nil?
      i += n_required_fields
      @fieldnames.delete_at(i)
      @fields.delete_at(i)
    end
    nil
  end

  # Returns the string representation of an optional field
  # @param optfield_tag [#to_sym] name of the optional field
  # @return [RGFA::Optfield] string representation of optional field
  # @return [nil] if optional field does not exist
  def optfield(optfield_tag)
    i = optional_fieldnames.index(optfield_tag.to_sym)
    return i.nil? ? nil : @fields[i + n_required_fields]
  end

  # Alias for {#add_optfield}
  # @see #add_optfield
  def <<(optfield)
    add_optfield(optfield)
  end

  # Three methods are dynamically created for each existing field name as well
  # as for each non-existing but valid optional field name.
  #
  # ---
  #  - (Object) <fieldname>(cast: false)
  # The value of the field.
  #
  # <b>Parameters:</b>
  # - +*cast*+ (Boolean) -- <i>(default: true)</i> if +false+,
  #   return original string, otherwise cast into ruby type
  #
  # <b>Returns:</b>
  # - (String, Hash, Array, Integer, Float) if field exists and +cast+ is true
  # - (String) if field exists and +cast+ is false
  # - (nil) if the field does not exist, but is a valid optional field name
  #
  # ---
  #  - (Object) <fieldname>!(cast: false)
  # Banged version of +<fieldname>+.
  #
  # <b>Parameters:</b>
  # - +*cast*+ (Boolean) -- <i>(default: true)</i> if +false+,
  #   return original string, otherwise cast into ruby type
  #
  # <b>Returns:</b>
  # - (String, Hash, Array, Integer, Float) if field exists and +cast+ is true
  # - (String) if field exists and +cast+ is false
  #
  # <b>Raises:</b>
  # - (RGFA::Line::TagMissingError) if the field does not exist
  #
  # ---
  #
  #  - (self) <fieldname>=(value)
  # Sets the value of a required or optional
  # field, or creates a new optional field if the fieldname is
  # non-existing but valid. In the latter case, the type of the
  # optional field is selected, depending on the class of +value+
  # (see RGFA::Optfield::new_autotype() method).
  #
  # <b>Parameters:</b>
  # - +*value*+ (String|Hash|Array|Integer|Float) value to set
  #
  # <b>Returns:</b>
  # - (self)
  #
  # ---
  #
  def method_missing(m, *args, &block)
    ms, var, i = process_unknown_method(m)
    if !i.nil?
      return (var == :set) ? (self[i] = args[0]) : get_field(i, *args)
    elsif ms =~ /^#{RGFA::Optfield::TAG_REGEXP}$/
      raise RGFA::Line::TagMissingError,
        "No value defined for tag #{ms}" if var == :bang
      return (var == :set) ? auto_create_optfield(ms, args[0]) : nil
    end
    super
  end

  # Redefines respond_to? to correctly handle dynamical methods.
  # @see #method_missing
  def respond_to?(m, include_all=false)
    retval = super
    if !retval
      pum_retvals = process_unknown_method(m)
      ms = pum_retvals[0]
      i = pum_retvals[2]
      return (!i.nil? or ms =~ /^#{RGFA::Optfield::TAG_REGEXP}$/)
    end
    return retval
  end

  # @return self
  # @param validate [Boolean] ignored (compatibility reasons)
  def to_rgfa_line(validate: true)
    self
  end

  # Equivalence check
  # @return [Boolean] does the line contains the same optional fields
  #   and all required and optional fields contain the same field values?
  # @see RGFA::Line::Link#==
  def ==(o)
    (o.fieldnames == self.fieldnames) and
      (o.fieldnames.all? {|fn|o.send(fn) == self.send(fn)})
  end

  # Validate the RGFA::Line instance
  # @raise if the field content is not valid
  # @return [void]
  def validate!
    self.class.validate_record_type!(self.record_type)
    validate_required_fields!
    validate_optional_fields!
    validate_record_type_specific_info!
    nil
  end

  private

  def []=(i, value)
    set_field(i, value)
  end

  def [](i)
    get_field(i, true)
  end

  def set_field(i, value)
    if i >= @fieldnames.size
      raise ArgumentError, "Line does not have a field number #{i}"
    end
    if i < n_required_fields
      @fields[i] = value
      validate_required_field!(i) if @validate
    else
      if value.nil?
        rm_optfield(@fieldnames[i])
      else
        @fields[i].value = value
      end
    end
  end

  def get_field(i, autocast = true)
    if i >= @fieldnames.size
      raise ArgumentError, "Line does not have a field number #{i}"
    end
    if i < n_required_fields
      if autocast and self.class::REQFIELD_CAST.has_key?(@fieldnames[i])
        return self.class::REQFIELD_CAST[@fieldnames[i]].call(@fields[i])
      else
        return @fields[i]
      end
    else
      return @fields[i].value(autocast)
    end
  end

  def n_required_fields
    self.class::REQFIELD_DEFINITIONS.size
  end

  def initialize_required_fields
    validate_reqfield_definitions! if @validate
    @fieldnames += self.class::REQFIELD_DEFINITIONS.map{|name,re| name.to_sym}
    validate_required_fields! if @validate
  end

  def initialize_optional_fields
    validate_optfield_types! if @validate
    if @fields.size > n_required_fields
      optfields = @fields[n_required_fields..-1].dup
      @fields = @fields[0,n_required_fields]
      optfields.each { |f| self << f.to_rgfa_optfield(validate: @validate) }
    end
  end

  def process_unknown_method(m)
    ms = m.to_s
    var = nil
    if ms[-1] == "!"
      var = :bang
      ms.chop!
    elsif ms[-1] == "="
      var = :set
      ms.chop!
    end
    i = @fieldnames.index(ms.to_sym)
    return ms, var, i
  end

  def auto_create_optfield(tagname, value, validate: @validate)
    return self if value.nil?
    self << RGFA::Optfield.new_autotype(tagname, value, validate: validate)
  end

  def validate_reqfield_definitions!
    if !self.class::REQFIELD_DEFINITIONS.kind_of?(Array)
      raise ArgumentError, "Argument 'reqfield_definitions' must be an Array"
    end
    names = []
    self.class::REQFIELD_DEFINITIONS.each do |name, regexp|
      if (self.methods+self.private_methods).include?(name.to_sym)
        raise RGFA::Line::InvalidFieldNameError,
          "Invalid name of required field, '#{name}' is a method of RGFA::Line"
      end
      if names.include?(name.to_sym)
        raise ArgumentError,
          "The names of required fields must be unique ('#{name}' found twice)"
      end
      names << name.to_sym
    end
  end

  def validate_optfield_types!
    if !self.class::OPTFIELD_TYPES.kind_of?(Hash)
      raise ArgumentError, "Argument 'optfield_types' must be a Hash"
    end
    self.class::OPTFIELD_TYPES.each do |name, type|
      if (self.methods+self.private_methods).include?(name.to_sym)
        raise RGFA::Line::InvalidFieldNameError,
          "Invalid name of optional field, '#{name}' is a method of RGFA::Line"
      end
      if required_fieldnames.include?(name.to_sym)
        raise ArgumentError,
          "The names of optional fields cannot be "+
          "identical to a required field name ('#{name}' found twice)"
      end
    end
  end

  def validate_required_field!(i)
    regexp = /^#{self.class::REQFIELD_DEFINITIONS[i][1]}$/
    if @fields[i] !~ regexp
      raise RGFA::Line::RequiredFieldTypeError,
        "Field n.#{i} ('#{@fieldnames[i]}') has a wrong format\n"+
        "expected: #{regexp}\ngot: #{@fields[i]}"
    end
  end

  def validate_required_fields!
    if @fields.size < n_required_fields
      raise RGFA::Line::RequiredFieldMissingError,
        "#{n_required_fields} required fields, #{@fields.size}) found\n"+
        "#{@fields.inspect}"
    end
    n_required_fields.times {|i| validate_required_field!(i)}
  end

  def validate_optional_field!(f)
    predefopt = self.class::OPTFIELD_TYPES.keys
    if predefopt.include?(f.tag)
      if self.class::OPTFIELD_TYPES[f.tag] != f.type
        raise RGFA::Line::PredefinedOptfieldTypeError,
          "Optional field #{f.tag} must be of type "+
            "#{self.class::OPTFIELD_TYPES[f.tag]}"
      end
    else
      if f.tag !~ /^[a-z][a-z0-9]$/
        raise RGFA::Line::CustomOptfieldNameError,
        "Invalid name of custom-defined optional field,"+
        "'#{f.tag}' is not in lower case"
      end
    end
    if required_fieldnames.include?(f.tag.to_sym)
      raise RGFA::Line::CustomOptfieldNameError,
        "Invalid name of custom-defined optional field, "+
        "'#{f.tag}' is a required field name"
    elsif (self.methods+self.private_methods).include?(f.tag.to_sym)
      raise RGFA::Line::CustomOptfieldNameError,
        "Invalid name of custom-defined optional field, "+
        "'#{f.tag}' is a method of RGFA::Line"
    end
  end

  def validate_optional_fields!
    found = []
    @fields[n_required_fields..-1].each do |optfield|
      validate_optional_field!(optfield)
      sym = optfield.tag.to_sym
      if found.include?(sym)
        raise RGFA::Line::DuplicateOptfieldNameError,
          "Optional tag '#{optfield.tag}' exists more than once"
      end
      found << sym
    end
  end

  def validate_record_type_specific_info!
  end

end

# Error raised if the record_type is not one of RGFA::Line::RECORD_TYPES
class RGFA::Line::UnknownRecordTypeError      < TypeError;     end

# Error raised if a field has the same name as a method of the class;
# This is required by the dynamic method generation system.
class RGFA::Line::InvalidFieldNameError       < ArgumentError; end

# Error raised if too less required fields are specified.
class RGFA::Line::RequiredFieldMissingError   < ArgumentError; end

# Error raised if the type of a required field does not match the
# validation regexp.
class RGFA::Line::RequiredFieldTypeError      < TypeError;     end

# Error raised if a non-predefined optional field uses upcase
# letters.
class RGFA::Line::CustomOptfieldNameError     < ArgumentError; end

# Error raised if an optional field tag name is used more than once.
class RGFA::Line::DuplicateOptfieldNameError  < ArgumentError; end

# Error raised if the type of a predefined optional field does not
# respect the specified type.
class RGFA::Line::PredefinedOptfieldTypeError < TypeError;     end

# Error raised if optional tag is not present
class RGFA::Line::TagMissingError             < NoMethodError; end

#
# Automatically require the child classes specified in the RECORD_TYPES hash
#
RGFA::Line::RECORD_TYPES.values.each do |rtclass|
  require_relative "../#{rtclass.downcase.gsub("::","/")}.rb"
end

# Extensions to the String core class.
#
class String

  # Parses a line of a RGFA file and creates an object of the correct record type
  # child class of {RGFA::Line}
  # @return [subclass of RGFA::Line]
  # @raise if the string does not comply to the RGFA specification
  # @param validate [Boolean] <i>(defaults to: +true+)</i>
  #   if false, turn off validations
  def to_rgfa_line(validate: true)
    split(RGFA::Line::SEPARATOR).to_rgfa_line(validate: validate)
  end

end

# Extensions to the Array core class.
#
class Array

  # Parses an array containing the fields of a RGFA file line and creates an
  # object of the correct record type child class of {RGFA::Line}
  # @return [subclass of RGFA::Line]
  # @raise if the fields do not comply to the RGFA specification
  # @param validate [Boolean] <i>(defaults to: +true+)</i>
  #   if false, turn off validations
  def to_rgfa_line(validate: true)
    record_type = self[0]
    RGFA::Line.validate_record_type!(record_type,self) unless !validate
    eval(RGFA::Line::RECORD_TYPES[record_type]).new(self[1..-1],
                                                    validate: validate)
  end

end