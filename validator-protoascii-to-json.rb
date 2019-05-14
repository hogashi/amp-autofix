system "ruby-protoc amphtml/validator/validator.proto"
require './amphtml/validator/validator.pb.rb'
require 'json'

# collect all of validation rules
protoascii_filenames = ['amphtml/validator/validator-main.protoascii'] + Dir.glob('amphtml/extensions/*/validator-*.protoascii')

protoascii = ''
protoascii_filenames.each {|file|
  protoascii += open(file).read.force_encoding('ASCII').scrub
}

rules = Amp::Validator::ValidatorRules.parse_from_text(protoascii)
puts rules.to_hash.to_json
# open('validation_rules.json', 'w', 0644).write(rules.to_hash.to_json)
