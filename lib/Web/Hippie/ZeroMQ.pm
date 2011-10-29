package Web::Hippie::ZeroMQ;

use strict;
use warnings;
our $VERSION = '0.01';
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

# required args for constructing ZeroMQ client
use Plack::Util::Accessor qw/
    bus
/;

sub prepare_app {
    my ($self) = @_;

    die "bus is a required builder argument for Web::Hippie::ZeroMQ"
        unless $self->bus;

    # our handlers for hippie actions
    mount '/_hippie' => builder {        
        # websocket/mxhr/poll handlers
        enable "+Web::Hippie";

        # AnyMQ
        enable "+Web::Hippie::Pipe", bus => $self->bus;

        # these are handlers for internal hippie events, NOT actual
        # URLs visited by the client
        # (/new_listener, /message, /error)
        sub {
            my $env = shift;
            my $channel = $env->{'hippie.args'};
            my $req = Plack::Request->new($env);

            if ($req->path eq '/new_listener') {
                # called when we get a new topic subscription

                die "Channel not found on new_listener" unless $channel;
                my $topic = $env->{'hippie.bus'}->topic($channel);

                warn "listener added";
                
                # subscribe client to events on $channel
                $env->{'hippie.listener'}->subscribe( $topic );
                return [ '200', [ 'Content-Type' => 'text/plain' ], [ "Now listening on $channel" ] ];

            } elsif ($req->path eq '/message') {
                # called when we are publishing a message

                die "Channel not found on message" unless $channel;
                my $topic = $env->{'hippie.bus'}->topic($channel);
                            
                my $msg = $env->{'hippie.message'};
                $msg->{time} = time;
                $msg->{address} = $env->{REMOTE_ADDR};

                return [ '200', [ 'Content-Type' => 'text/plain' ], [ "Event published on $channel" ] ];
            } else {
                # other message (should only be error)
                # make sure stuff is kosher
                
                my $h = $env->{'hippie.handle'}
                    or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "missing handle" ] ];

                if ($req->path eq '/error') {
                    warn "==> disconnecting $h (error or timeout)\n";
                } else {
                    die "unknown hippie message";
                }
            }

            # we didn't handle anything
            return [ '404', [ 'Content-Type' => 'text/plain' ], [ "unknown event server path " . $req->path ] ];
        };
    };
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Web::Hippie::ZeroMQ - Comet/Long-poll event server that can talk to a
ZeroMQ server

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
      enable "+Web::Hippie::ZeroMQ", bus => $bus;
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
AnyMQ::ZeroMQ.

=head1 SEE ALSO

L<Web::Hippie::Pipe>, L<Web::Hippie::Pipe>, L<AnyMQ::ZeroMQ>,
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
