# An unordered group line of a GFA2 file
class RGFA::Line::UnorderedGroup < RGFA::Line

  RECORD_TYPE = :U
  POSFIELDS = {:"1.0" => nil,
               :"2.0" => [:pid, :items]}
  PREDEFINED_TAGS = []
  FIELD_ALIAS = {}
  DATATYPE = {
    :pid => :optional_identifier_gfa2,
    :items => :generic,
  }

  define_field_methods!

end
