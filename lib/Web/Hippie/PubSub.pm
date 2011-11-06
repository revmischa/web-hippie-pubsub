package Web::Hippie::PubSub;

use strict;
use warnings;
our $VERSION = '0.02';
use parent 'Plack::Middleware';

use AnyEvent::Socket;
use AnyEvent::Handle;
use Plack::Request;
use Plack::Builder;
use Plack::App::Cascade;
use Web::Hippie;
use Web::Hippie::Pipe;
use JSON;
use Carp qw/croak cluck/;

# required args for constructing PubSub client
use Plack::Util::Accessor qw/
    bus
/;

sub call {
    my ($self, $env) = @_;
    my $res = $self->app->($env);
    return $res;
}

sub prepare_app {
    my ($self) = @_;

    die "bus is a required builder argument for Web::Hippie::PubSub"
        unless $self->bus;

    my $builder = Plack::Builder->new;

    # websocket/mxhr/poll handlers
    $builder->add_middleware('+Web::Hippie');
    
    # AnyMQ stuff for Web::Hippie
    $builder->add_middleware('+Web::Hippie::Pipe', bus => $self->bus);
    
    # our simple publish/subscribe event code
    $builder->add_middleware(sub {
        my $app = shift;
        return sub {
            # these are handlers for internal hippie events, NOT actual
            # URLs visited by the client
            # (/new_listener, /message, /error)
            my $env = shift;
            my $channel = $env->{'hippie.args'};
            my $req = Plack::Request->new($env);

            if ($req->path eq '/new_listener') {
                # called when we get a new topic subscription

                return [ 400, [], [ "Channel is required for new_listener" ] ] unless $channel;
                my $topic = eval { $env->{'hippie.bus'}->topic($channel) };
                unless ($topic) {
                    warn "Could not get topic for channel $channel: $@";
                    return [ 500, [ 'Content-Type' => 'text/plain' ], [ "Unable to create listener for channel $channel" ] ];
                }

                # subscribe client to events on $channel
                $env->{'hippie.listener'}->subscribe($topic);
                my $res = $app->($env);
                return $res || [ '200', [ 'Content-Type' => 'text/plain' ], [ "Now listening on $channel" ] ];

            } elsif ($req->path eq '/message') {
                # called when we are publishing a message

                # get message channel
                return [ '400', [ 'Content-Type' => 'text/plain' ], [ "Channel is required" ] ] unless $channel;
                my $topic = $env->{'hippie.bus'}->topic($channel);

                # get message, tack on sent time and from addr
                my $msg = $env->{'hippie.message'};
                $msg->{time} = time;
                $msg->{address} = $env->{REMOTE_ADDR};

                # publish event, but don't notify local listeners (or
                # they will receive a duplicate event)
                $topic->publish($msg);

                my $res = $app->($env);
                return $res || [ '200', [ 'Content-Type' => 'text/plain' ], [ "Event published on $channel" ] ];
            } else {
                # other message (should only be error)
                # make sure stuff is kosher

                my $res = $app->($env);
                
                my $h = $env->{'hippie.handle'}
                    or return $res || [ '400', [ 'Content-Type' => 'text/plain' ], [ "missing handle" ] ];

                if ($req->path eq '/error') {
                    warn "==> disconnecting $h (error or timeout)\n";
                } else {
                    warn "unknown hippie message: " . $req->path;
                    return $res || [ '500', [ 'Content-Type' => 'text/plain' ], [ 'Unknown error' ] ];
                }
            }

            my $res = $app->($env);
            
            # we didn't handle anything
            return $res || [ '404', [ 'Content-Type' => 'text/plain' ], [ "unknown event server path " . $req->path ] ];
        }
    });

    $self->app( $builder->to_app($self->app) );
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Web::Hippie::PubSub - Comet/Long-poll event server using AnyMQ

=head1 SYNOPSIS

  use Plack::Builder;
  use AnyMQ;
  use AnyMQ::ZeroMQ;

  my $bus = AnyMQ->new_with_traits(
    traits            => [ 'ZeroMQ' ],
    subscribe_address => 'tcp://localhost:4001',
    publish_address   => 'tcp://localhost:4000',
  );

  # your plack application
  my $app = sub { ... }

  builder {
    # mount hippie server
    mount '/_hippie' => builder {
      enable "+Web::Hippie::PubSub", bus => $bus;
      sub {
        my $env = shift;
        my $args = $env->{'hippie.args'};
        my $handle = $env->{'hippie.handle'};
        # Your handler based on PATH_INFO: /init, /error, /message
      }
    };
    mount '/' => my $app;
  };

=head1 DESCRIPTION

This module adds publish/subscribe capabilities to L<Web::Hippie> using
AnyMQ.

See eg/event_server.psgi for example usage.

=head1 SEE ALSO

L<Web::Hippie>, L<Web::Hippie::Pipe>, L<AnyMQ>,
L<ZeroMQ::PubSub>

=head1 AUTHOR

Mischa Spiegelmock E<lt>revmischa@cpan.orgE<gt>


Based on work by:

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

Jonathan Rockway E<lt>jrockway@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
