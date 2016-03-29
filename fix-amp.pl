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

    sub allowed_tagnames {
        my ($self) = @_;

        return $self->{allowed_tagnames} if $self->{allowed_tagnames};
        my $names = {};

        my $defs = $self->validation_rules->{tags};
        for my $def (@$defs) {
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
