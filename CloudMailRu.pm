#! /usr/bin/env perl
###################################################
#
#  Copyright (C) 2013 KPEBETKA <KPEBETKA@my.com>
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
###################################################

package CloudMailRu;

use lib $ENV{'SHUTTER_ROOT'}.'/share/shutter/resources/modules';

use utf8;
use strict;
use POSIX qw(strftime setlocale);
use Locale::gettext;
use Glib qw/TRUE FALSE/; 

use Shutter::Upload::Shared;
our @ISA = qw(Shutter::Upload::Shared);

my $d = Locale::gettext->domain("shutter-upload-plugins");
$d->dir( $ENV{'SHUTTER_INTL'} );

my %upload_plugin_info = (
	'module' => "CloudMailRu",
	'url' => "https://cloud.mail.ru/",
	'registration' => "https://mail.ru/signup",
	'description' => $d->get( "Upload screenshots into your CloudMailRu" ),
	'supports_anonymous_upload' => FALSE,
	'supports_authorized_upload' => TRUE,
	'supports_oauth_upload' => FALSE,
);

sub url_escape($) {
	my ($string) = @_;
		utf8::encode $string if utf8::is_utf8($string);
	$string =~ s/([^A-Za-z0-9\-._~])/sprintf('%%%02X',ord($1))/ge;
	return $string;
}

sub url_query {
	join('&',map { url_escape($_).'='.url_escape( $_[0]{$_} ) } keys %{ $_[0] } );
}

sub new {
	my $class = shift;

	my $self = $class->SUPER::new( shift, shift, shift, shift, shift, shift );
	bless $self, $class;

	return $self;
}

sub init {
	my $self = shift;
	
	use LWP::UserAgent;
	use HTTP::Request::Common;
	use HTTP::Cookies;

	BEGIN {
  		if (eval { require JSON::XS; }) { JSON::XS->import() }
  		elsif (eval { require JSON; }) { JSON->import() }
  		else { die "JSON::XS or JSON required"; }
	}
	
	return TRUE;
}

sub upload {
	my ( $self, $upload_filename, $username, $password ) = @_;

	$self->{_filename} = $upload_filename;
	$self->{_username} = $username;
	$self->{_password} = $password;

	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;
	
	
	our $token;
	our $hash;
	our $name;
	our $size;
	our $uptime;
	our $cloclo;
	our $dir = "/Screenshots";
	our ($domain) = $username =~ m{\@(.+)$};	

	if ( $username ne "" && $password ne "" ) {

		eval{

			my $ua = LWP::UserAgent->new;
			$ua->cookie_jar(HTTP::Cookies->new(autosave => 1,));
			wtf:{
					{
						my $url = "https://auth.mail.ru/cgi-bin/auth?" . url_query({ Login => $username, Password => $password, Domain => $domain });
						my $req = GET $url;
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
					}
	
					{
						my $url = "http://cloud.mail.ru/api/v1/tokens?".url_query({ email => $username });
						my $req = GET $url;
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $resp = decode_json($res->decoded_content);
						$token = $resp->{body}{token};
					}
					{
						my $url = "https://cloud.mail.ru/api/v1/folder/add";
						my ($folder,$name) = $dir =~ m{^(.*/)([^/]+)$};
						my $body = url_query({
							add => encode_json([{
							folder => $folder,
							name => $name
						}]),
							api => 1,
							email => $username,
							storage => 'home',
							token => $token,
						});
						my $req = HTTP::Request->new(POST => $url);
						$req->content( $body );
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $resp = decode_json($res->decoded_content);
						if ($resp->{status} == 200) {}
						else {
							if ( $resp->{body}{'add[0].name'}{error} eq 'exists' ) {}
							else {
								$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
							}
						}
					}

					{
						my $url = 'https://dispatcher.cloud.mail.ru/u';
						my $req = GET $url;
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $message = $res->decoded_content;
						($cloclo) = $message =~ m{^(\S+)\s+}xmo;
					}
	
					{
						my $req = POST $cloclo, Content_Type => 'multipart/form-data', Content => [file => [$upload_filename]];
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $message = $res->decoded_content;
						$message =~ s{\s+$}{}s;
						($hash,$name,$size) = split /;/,$message;
					}

					{
						$name =~ s/\s/_/g;
						$uptime = strftime "%Y_%B_%d-%H_%M_%S", localtime;
						utf8::decode $name;
						utf8::decode $uptime;

						my $url = "https://cloud.mail.ru/api/v1/file/add";
						my $body = url_query({
							folder => $dir,
							files => encode_json([{
								name => "$uptime\_$name",
								size => $size,
								hash => $hash,
							}]),
							api => 1,
							email => $username,
							storage => 'home',
							token => $token,
						});
						my $req = HTTP::Request->new(POST => $url);
						$req->content( $body );
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $resp = decode_json($res->decoded_content);
						if ($resp->{status} == 200) {}
						else {
							$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						}
					}

					{
						my $url = "https://cloud.mail.ru/api/v1/file/share";
						my $body = url_query({
							ids => encode_json([ "$dir/$uptime\_$name" ]),
							api => 1,
							email => $username,
							storage => 'home',
							token => $token,
						});
						my $req = HTTP::Request->new(POST => $url);
						$req->content( $body );
						my $res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						my $resp = decode_json($res->decoded_content);
						if ($resp->{status} == 200) {}
						else {
							$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						}

						$self->{_links}->{'direct_link'} = "https://cloud.mail.ru$resp->{body}[0]{url}{web}";
						$self->{_links}->{'short_link'} = "https://cloud.datacloudmail.ru/weblink/view/$resp->{body}[0]{id}";					

						$url = "https://auth.mail.ru/cgi-bin/logout";
						$req = GET $url;
						$res = $ua->request($req);
						$res->code == 200 or do{ $self->{_links}{'status'} = $res->code; last wtf };
						$self->{_links}{'status'} = 200;
		
					}
				}
			}

		}

		return %{ $self->{_links} };
}

1;
