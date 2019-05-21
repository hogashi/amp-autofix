# sketch-amp-autofix

## バリデーションルールのJSONつくりたい!

```
git submodule update --init
brew install protobuf
gem install bundler
bundle install --path vendor/bundle
bundle exec -- ruby validator-protoascii-to-json.rb > validation_rules.json
```

## 自動でAMPをHTMLに直したい!

```
carton install
cat examples/disallowed_attributes.html | carton exec -- perl fix-amp.pl
```
