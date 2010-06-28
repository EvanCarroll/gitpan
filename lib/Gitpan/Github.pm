use MooseX::Declare;

use Net::GitHub::V2::NoRepo;

role Net::GitHub::V2::NoRepo
  with Gitpan::Github::ResponseReader
  with Gitpan::CanBackoff
{
    method default_success_check($response) {
        return 0 unless $response;

        if( my $error = $self->is_network_error($response) ) {
            croak "Looks like the network is down: $error";
        }

        return 0 if $self->is_too_many_requests($response);
        return 1;
    }


    # Monkey patch the baseline JSON fetcher in Net::GitHub::V2
    # to be more robust
    {
        my $orig = Net::GitHub::V2::NoRepo->can("get_json_to_obj");
        my $new  = sub {
            my $self = shift;
            my @args = @_;

            $self->do_with_backoff(
                times        => 6,
                code         => sub {
                    return $self->$orig(@args);
                }
            );
        };

        no warnings 'redefine';
        *get_json_to_obj = $new;
    }
}


class Gitpan::Github
  extends Net::GitHub::V2
{
    use perl5i::2;
    use Path::Class;
    use MooseX::AlwaysCoerce;

    has "+owner" =>
      default   => 'gitpan';

    has "+login" =>
      default   => 'gitpan';

    method exists_on_github( Str :$owner?, Str :$repo? ) {
        $owner //= $self->owner;
        $repo  //= $self->repo;

        my $info = $self->repos->show( $owner, $repo );
        return $self->get_response_errors($info)->size ? 0 : 1;
    }

    method create_repo( Str :$repo?, Str :$desc, Str :$homepage, Str :$is_public ) {
        $repo //= $self->repo;

        return $self->repos->create( $repo, $desc, $homepage, $is_public );
    }

    method maybe_create( Str :$repo?, Str :$desc, Str :$homepage, Str :$is_public ) {
        $repo //= $self->repo;

        return $repo if $self->exists_on_github();
        return $self->create_repo( @_ );
    }
}
