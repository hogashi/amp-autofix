system "ruby-protoc amphtml/validator/validator.proto"
require './amphtml/validator/validator.pb.rb'

protoascii = open('amphtml/validator/validator.protoascii').read.force_encoding('ASCII').scrub

rules = Amp::Validator::ValidatorRules.parse_from_text(protoascii)
rules.attr_lists

require 'pp'
pp rules.to_hash
