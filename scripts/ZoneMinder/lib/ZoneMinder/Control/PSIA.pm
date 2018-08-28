# =========================================================================
#
# PSIA IP Control Protocol Module, $Date: $, $Revision: $
# Jonathan Lassoff (jof@thejof.com) -- 2018
#
#
# ==========================================================================
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# ==========================================================================
#

package ZoneMinder::Control::PSIA;

use 5.006;
#use strict;
use warnings;

require ZoneMinder::Base;
require ZoneMinder::Control;

our @ISA = qw(ZoneMinder::Control);

our $REALM = 'TV-IP450PI';
our $USERNAME = 'admin';
our $PASSWORD = '';
our $ADDRESS = '';

use ZoneMinder::Logger qw(:all);
use ZoneMinder::Config qw(:all);
use ZoneMinder::Database qw(zmDbConnect);

sub new
{
    my $class = shift;
    my $id = shift;
    my $self = ZoneMinder::Control->new( $id );
    bless( $self, $class );
    srand( time() );
    return $self;
}

our $AUTOLOAD;

sub AUTOLOAD
{
    my $self = shift;
    my $class = ref($self) || croak( "$self not object" );
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    if ( exists($self->{$name}) )
    {
        return( $self->{$name} );
    }
    Fatal( "Can't access $name member of object of class $class" );
}

sub open
{
    my $self = shift;
    $self->loadMonitor();

    my ( $protocol, $username, $password, $address )
       = $self->{Monitor}->{ControlAddress} =~ /^(https?:\/\/)?([^:]+):([^\/@]+)@(.*)$/;
    if ( $username ) {
        $USERNAME = $username;
        $PASSWORD = $password;
        $ADDRESS = $address;
    } else {
        Error( "Failed to parse auth from address");
        $ADDRESS = $self->{Monitor}->{ControlAddress};
    }
    if (not $ADDRESS =~ /:/) {
        Error("You generally need to also specify the port.  I will append :80");
        $ADDRESS .= ':80';
    }

    use LWP::UserAgent;
    $self->{ua} = LWP::UserAgent->new;
    $self->{ua}->agent( "ZoneMinder Control Agent/".$ZoneMinder::Base::ZM_VERSION );
    $self->{state} = 'closed';
#   credentials:  ("ip:port" (no prefix!), realm (string), username (string), password (string)
    Debug( "sendCmd credentials control address:'".$ADDRESS
            ."'  realm:'" . $REALM
            . "'  username:'" . $USERNAME
            . "'  password:'".$PASSWORD
            ."'"
    ); 
    $self->{ua}->credentials($ADDRESS, $REALM, $USERNAME, $PASSWORD);

    # Detect REALM
    my $req = HTTP::Request->new(GET=>"http://".$ADDRESS."/PSIA/PTZ/channels");
    my $res = $self->{ua}->request($req);

    if ($res->is_success) {
        $self->{state} = 'open';
        return;
    } elsif (! $res->is_success) {
        Debug("Need newer REALM");
        if ( $res->status_line() eq '401 Unauthorized' ) {
            my $headers = $res->headers();
			foreach my $k ( keys %$headers ) {
			    Debug("Initial Header $k => $$headers{$k}");
			}  # end foreach
			if ( $$headers{'www-authenticate'} ) {
                my ($auth, $tokens) = $$headers{'www-authenticate'} =~ /^(\w+)\s+(.*)$/;
                if ($tokens =~ /\w+="([^"]+)"/i) {
                    $REALM = $1;
                    Debug("Changing REALM to $REALM");
                    $self->{ua}->credentials($ADDRESS, $REALM, $USERNAME, $PASSWORD);
                } # end if
            } else {
                Debug("No WWW-Authenticate header");
            } # end if www-authenticate header
        } # end if $res->status_line() eq '401 Unauthorized'
    } # end elsif ! $res->is_success
}

sub close
{
    my $self = shift;
    $self->{state} = 'closed';
}

sub printMsg
{
    my $self = shift;
    my $msg = shift;
    my $msg_len = length($msg);

    Debug( $msg."[".$msg_len."]" );
}

sub sendGetRequest {
    my $self = shift;
    my $url_path = shift;

    my $result = undef;

    my $url = "http://".$ADDRESS . $url_path;
    my $req = HTTP::Request->new(GET=>$url);

    my $res = $self->{ua}->request($req);

    if ($res->is_success) {
        $result = !undef;
    } else {
        if ( $res->status_line() eq '401 Unauthorized' ) {
            Error( "Error check failed, trying again: USERNAME: $USERNAME realm: $REALM password: " . $PASSWORD );
            Error("Content was " . $res->content() );
            my $res = $self->{ua}->request($req);
            if ( $res->is_success ) {
                $result = !undef;
            } else {
                Error("Content was " . $res->content() );
            }
        }
        if ( ! $result ) {
            Error("Error check failed: '".$res->status_line());
        }
    }
    return($result);
}
sub sendPutRequest {
    my $self = shift;
    my $url_path = shift;
    my $content = shift;

    my $result = undef;

    my $url = "http://".$ADDRESS . $url_path;
    my $req = HTTP::Request->new(PUT=>$url);
    if(defined($content)) {
        $req->content_type("application/x-www-form-urlencoded; charset=UTF-8");
        $req->content('<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $content);
    }

    my $res = $self->{ua}->request($req);

    if ($res->is_success) {
        $result = !undef;
    } else {
        if ( $res->status_line() eq '401 Unauthorized' ) {
            Error( "Error check failed, trying again: USERNAME: $USERNAME realm: $REALM password: " . $PASSWORD );
            Error("Content was " . $res->content() );
            my $res = $self->{ua}->request($req);
            if ( $res->is_success ) {
                $result = !undef;
            } else {
                Error("Content was " . $res->content() );
            }
        }
        if ( ! $result ) {
            Error( "Error check failed: '".$res->status_line()."' cmd:'".$cmd."'" );
        }
    }
    return($result);
}
sub sendDeleteRequest {
    my $self = shift;
    my $url_path = shift;

    my $result = undef;

    my $url = "http://" . $ADDRESS . $url_path;
    my $req = HTTP::Request->new(DELETE=>$url);
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        $result = !undef;
    } else {
        if ( $res->status_line() eq '401 Unauthorized' ) {
            Error( "Error check failed, trying again: USERNAME: $USERNAME realm: $REALM password: " . $PASSWORD );
            Error("Content was " . $res->content() );
            my $res = $self->{ua}->request($req);
            if ( $res->is_success ) {
                $result = !undef;
            } else {
                Error("Content was " . $res->content() );
            }
        }
        if ( ! $result ) {
            Error( "Error check failed: '".$res->status_line()."' cmd:'".$cmd."'" );
        }
    }
    return($result);
}

sub move
{
    my $self = shift;
    my $panPercentage = shift;
    my $tiltPercentage = shift;
    my $zoomPercentage = shift;

    my $cmd = "set_relative_pos&posX=$panSteps&posY=$tiltSteps";
    my $ptzdata = '<PTZData version="1.0" xmlns="urn:psialliance-org">';
    $ptzdata .= '<pan>' . $panPercentage . '</pan>';
    $ptzdata .= '<tilt>' . $tiltPercentage . '</tilt>';
    $ptzdata .= '<zoom>' . $zoomPercentage . '</zoom>';
    $ptzdata .= '<Momentary><duration>500</duration></Momentary>';
    $ptzdata .= '</PTZData>';
    $self->sendPutRequest("/PSIA/PTZ/channels/1/momentary", $ptzdata);
}

sub moveRelUpLeft
{
    my $self = shift;
    Debug( "Move Up Left" );
    $self->move(-50, 50, 0);
}

sub moveRelUp
{
    my $self = shift;
    Debug( "Move Up" );
    $self->move(0, 50, 0);
}

sub moveRelUpRight
{
    my $self = shift;
    Debug( "Move Up Right" );
    $self->move(50, 50, 0);
}

sub moveRelLeft
{
    my $self = shift;
    Debug( "Move Left" );
    $self->move(-50, 0, 0);
}

sub moveRelRight
{
    my $self = shift;
    Debug( "Move Right" );
    $self->move(50, 0, 0);
}

sub moveRelDownLeft
{
    my $self = shift;
    Debug( "Move Down Left" );
    $self->move(-50, -50, 0);
}

sub moveRelDown
{
    my $self = shift;
    Debug( "Move Down" );
    $self->move(0, -50, 0);
}

sub moveRelDownRight
{
    my $self = shift;
    Debug( "Move Down Right" );
    $self->move(50, -50, 0);
}

sub zoomRelTele
{
    my $self = shift;
    Debug("Zoom Relative Tele");
    $self->move(0, 0, 50);
}

sub zoomRelWide
{
    my $self = shift;
    Debug("Zoom Relative Wide");
    $self->move(0, 0, -50);
}


sub presetClear
{
    my $self = shift;
    my $params = shift;
    my $preset_id = $self->getParam($params, 'preset');
    my $url_path = "/PSIA/PTZ/channels/1/presets/" . $preset_id;
    $self->sendDeleteRequest($url_path);
}


sub presetSet
{
    my $self = shift;
    my $params = shift;

    my $preset_id = $self->getParam($params, 'preset');

    my $dbh = zmDbConnect(1);
    my $sql = 'SELECT * FROM ControlPresets WHERE MonitorId = ? AND Preset = ?';
    my $sth = $dbh->prepare($sql)
        or Fatal("Can't prepare sql '$sql': " . $dbh->errstr());
    my $res = $sth->execute($self->{Monitor}->{Id}, $preset_id)
        or Fatal("Can't execute sql '$sql': " . $sth->errstr());
    my $control_preset_row = $sth->fetchrow_hashref();
    my $new_label_name = $control_preset_row->{'Label'};

    my $url_path = "/PSIA/PTZ/channels/1/presets/" . $preset_id;
    my $ptz_preset_data = '<PTZPreset>';
    $ptz_preset_data .= '<id>' . $preset_id . '</id>';
    $ptz_preset_data .= '<presetName>' . $new_label_name . '</presetName>';
    $ptz_preset_data .= '</PTZPreset>';
    $self->sendPutRequest($url_path, $ptz_preset_data);
}

sub presetGoto
{
    my $self = shift;
    my $params = shift;
    my $preset_id = $self->getParam($params, 'preset');

    my $url_path = '/PSIA/PTZ/channels/1/presets/' . $preset_id . '/goto';

    $self->sendPutRequest($url_path);
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

ZoneMinder::Control::PSIA - Perl extension for Physical Security
    Interoperability Alliance, IP Media Devices

=head1 SYNOPSIS

  use ZoneMinder::Database;
  stuff this in /usr/share/perl5/ZoneMinder/Control , then eat a sandwich

=head1 DESCRIPTION

Stub documentation for ZoneMinder::Control::PSIA

=head2 EXPORT

None by default.



=head1 SEE ALSO

Read the comments at the beginning of this file to see the usage for zoneminder 1.25.0


=head1 AUTHOR

Jonathan Lassoff

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018 by Jonathan Lassof

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut

