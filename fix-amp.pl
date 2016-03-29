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
        $tag->remove_tag;
    }

    sub is_allowed_tagname {
        my ($self, $name) = @_;

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
                    warn "valid $name = $value";
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
            return $def if $def->{name} eq $name;
        }
    }

    # returns: (is_valid, normalized_value)
    sub normalize_attribute_value {
        my ($self, $def, $value) = @_;
        if (exists $def->{value}) {
            return ($value eq $def->{value}, $def->{value});
        }

        # We always treat as case insensitive for loose validation
        for my $key (qw{value_regex value_regex_casei}) {
            if (exists $def->{$key}) {
                my $value_regex = $def->{$key};
                my $is_valid = $value =~ qr{\A$value_regex\Z}i;
                my ($valid_value) = $value_regex =~ m{\A\(?([^|]+)|};
                return ($is_valid, $valid_value);
            }
        }

        1;
    }

    sub fix_attribute_value {
        my ($self, $def, $value) = @_;
        undef;
    }

    sub collect_attr_defs {
        my ($self, $name) = @_;

        my $defs;
        my $validation_rules = $self->validation_rules;

        for my $tag (@{ $validation_rules->{tags} }) {
            if ($tag->{tag_name} eq $name) {
                push @$defs, @{$tag->{attrs}};
            }
        }


        for my $attrs (@{$self->validation_rules->{attr_lists}}) {
            if ($attrs->{name} eq '$GLOBAL_ATTRS') {
                push @$defs, @{$attrs->{attrs}};
            }
        }

        # support layout without parsing amp_layout because users don't write layout directly
        push @$defs, {
            name => 'layout',
        };

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
