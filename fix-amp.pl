use strict;
use warnings;
use Encode qw(decode_utf8 encode_utf8);

package AmpFilter {
    use HTML::Filter::Callbacks;
    use JSON::XS;
    use File::Slurp;

    sub new {
        my ($class) = @_;
        bless {}, $class;
    }

    sub fix {
        my ($self, $html) = @_;

        $self->filter->process($html);
    }

    sub filter {
        my ($self) = @_;

        my $filter = HTML::Filter::Callbacks->new;

        $filter->add_callbacks(
            '*' => {
                start => sub {
                    my ($tag, $filter) = @_;
                    $self->filter_remove_tag($tag);
                    return if $tag->{is_removed};
                    $self->filter_attribute($tag);
                },
                end => sub {
                    my ($tag, $filter) = @_;
                    $self->filter_remove_tag($tag);
                },
            },
        );

        $filter;
    }

    sub filter_remove_tag {
        my ($self, $tag) = @_;
        return if $self->is_allowed_tagname($tag->name);
        warn "remove @{[ $tag->as_string ]}";
        $tag->remove_tag;
    }

    sub is_allowed_tagname {
        my ($self, $name) = @_;

        $name = uc $name;
        !! $self->allowed_tagnames->{$name};
    }

    sub filter_attribute {
        my ($self, $tag) = @_;

        my @attrs_result;

        my $attr_defs = $self->collect_attr_defs($tag->name);

        my @attrs = @{$tag->{attrs}};
        while (my ($name, $value) = splice(@attrs, 0, 2)) {
            if (my $def = $self->allowed_attribute($attr_defs, $name)) {
                $value = $tag->_remove_quote($value);
                my ($is_valid_value, $normalized_value) = $self->normalize_attribute_value($def, $value);
                unless ($is_valid_value) {
                    $tag->{is_dirty} = 1;
                    $value = $normalized_value;
                }
                if (defined $value) {
                    push @attrs_result, $name, qq{"$value"};
                    next;
                }
            }
            warn "invalid $name";
            $tag->{is_dirty} = 1;
        }
        $tag->{attrs} = [@attrs_result];
    }

    sub allowed_attribute {
        my ($self, $defs, $name) = @_;

        for my $def (@$defs) {
            return $def if $name eq $def->{name};
            for my $alternative_name (@{$def->{alternative_names}}) {
                return $def if $name eq $alternative_name;
            }
        }
    }

    # returns: (is_valid, normalized_value)
    sub normalize_attribute_value {
        my ($self, $def, $value) = @_;

        # case sensitive value
        if (exists $def->{value} && (scalar @{ $def->{value} } > 0)) {
            for my $def_value (@{ $def->{value} }) {
                if ($value eq $def_value) {
                    return (1, $def_value);
                }
                # normalize when lowercase is correct
                if (lc $value eq $def_value) {
                    return (0, lc $def_value);
                }
                # normalize when uppercase is correct
                if (uc $value eq $def_value) {
                    return (0, uc $def_value);
                }
            }

            # return first value when not valid
            return (0, $def->{value}[0]);
        }

        # case insensitive value
        if (exists $def->{value_casei} && (scalar @{ $def->{value_casei} } > 0)) {
            for my $def_value_casei (@{ $def->{value_casei} }) {
                # case insensitive value is always lowercase
                if (lc $value eq $def_value_casei) {
                    return (1, $def_value_casei);
                }
            }

            # return first value when not valid
            return (0, $def->{value_casei}[0]);
        }

        # case sensitive value in regular expression
        my $value_regex = $def->{value_regex};
        if ($value_regex) {
            my $is_valid = $value =~ qr{\A$value_regex\Z};
            if ($is_valid) {
                return (1, $value);
            }
            # normalize when lowercase is correct
            $is_valid = lc $value =~ qr{\A$value_regex\Z};
            if ($is_valid) {
                return (0, lc $value);
            }
            # normalize when uppercase is correct
            $is_valid = uc $value =~ qr{\A$value_regex\Z};
            if ($is_valid) {
                return (0, uc $value);
            }

            my ($extracted_default_value) = $value_regex =~ m{\A\(?([^|]+)|};
            $is_valid = $extracted_default_value =~ qr{\A$value_regex\Z};
            if ($is_valid) {
                return (0, $extracted_default_value);
            }

            return (0, undef);
        }

        # case insensitive value in regular expression
        my $value_regex_casei = $def->{value_regex_casei};
        if ($value_regex_casei) {
            my $is_valid = $value =~ qr{\A$value_regex_casei\Z}i;
            if ($is_valid) {
                return (1, $value);
            }

            my ($extracted_default_value) = $value_regex_casei =~ m{\A\(?([^|]+)|};
            my $extract_default_value_is_valid = $extracted_default_value =~ qr{\A$value_regex_casei\Z}i;
            if ($extract_default_value_is_valid) {
                return (0, $extracted_default_value);
            }

            return (0, undef);
        }

        1;
    }

    sub collect_attr_defs {
        my ($self, $name) = @_;

        $name = uc $name;

        my $defs;
        my $attr_lists = {'$GLOBAL_ATTRS' => 1};
        my $validation_rules = $self->validation_rules;

        for my $tag (@{ $validation_rules->{tags} }) {
            if ($tag->{tag_name} eq $name) {
                push @$defs, @{$tag->{attrs}};
                if (exists $tag->{attr_lists}) {
                    $attr_lists->{$_} = 1 for @{$tag->{attr_lists}};
                }
                if (exists $tag->{amp_layout}) {
                    $attr_lists->{'$AMP_LAYOUT_ATTRS'} = 1;
                }
            }
        }
        for my $attrs (@{$self->validation_rules->{attr_lists}}) {
            if ($attr_lists->{$attrs->{name}}) {
                push @$defs, @{$attrs->{attrs}};
            }
        }

        $defs;
    }

    sub allowed_tagnames {
        my ($self) = @_;

        return $self->{allowed_tagnames} if $self->{allowed_tagnames};
        my $names = {};

        my $defs = $self->validation_rules->{tags};
        for my $def (@$defs) {
            next if $def->{mandatory_parent}; # skip because we are working on blog article, not whole html
            $names->{$def->{tag_name}} = 1;
        }

        $self->{allowed_tagnames} = $names;
    }

    sub validation_rules {
        my ($self) = @_;
        return $self->{rules} if $self->{rules};

        $self->{rules} = do {
            local $/;
            my $content = read_file('validation_rules.json');
            decode_json $content;
        };
    }
};

my $content = do {
    local $/;
    decode_utf8 scalar(<STDIN>);
};

my $filter = AmpFilter->new;
my $fixed = $filter->fix($content);
print encode_utf8 $fixed;
