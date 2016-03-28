system "ruby-protoc amphtml/validator/validator.proto"
require './amphtml/validator/validator.pb.rb'

protoascii = open('amphtml/validator/validator.protoascii').read

rules = Amp::Validator::ValidatorRules.parse_from_text(protoascii)
# rules.attr_lists

require 'pp'
pp rules.to_hash.keys

# -------

# validator_rules = Amp::Validator::ValidatorRules.new
# p validator_rules
# p validator_rules.merge_from_string(open('amphtml/validator/validator.protoascii').read)

# s = ProtocolBuffers::TextScanner.new(open('amphtml/validator/validator.protoascii').read)

# p msg = Test::MyMessage.new(:myField => 'zomgkittenz')
# open("test_msg", "wb") do |f|
#   msg.serialize(f)
# end
# p encoded = msg.serialize_to_string # or msg.to_s
# p Test::MyMessage.parse(encoded) == msg # true
