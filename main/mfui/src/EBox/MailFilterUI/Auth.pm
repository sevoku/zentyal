# Copyright (C) 2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

package EBox::MailFilterUI::Auth;
use base qw(EBox::ThirdParty::Apache2::AuthCookie);

use EBox;
use EBox::CGI::Run;
use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::Internal;
use EBox::Exceptions::Lock;
use EBox::Ldap;
use EBox::MailFilterUI;
use Crypt::Rijndael;
use Apache2::Connection;
use Apache2::RequestUtil;
use Apache2::Const qw(:common HTTP_FORBIDDEN HTTP_MOVED_TEMPORARILY);
use EBox::MailFilterUI;
use EBox::MailFilterUI::DBEngine;

use MIME::Base64;
use Digest::MD5;
use Fcntl qw(:flock);
use File::Basename;
use Error qw(:try);

# By now, the expiration time for session is hardcoded here
use constant EXPIRE => 3600; #In seconds  1h
# By now, the expiration time for a script session
use constant MAX_SCRIPT_SESSION => 10; # In seconds

# Method: _savesession
#
# Parameters:
#
#   - user name
#   - password
#   - session id: if the id is undef, it creates a new one
#   - key: key for rijndael, if sid is undef creates a new one
# Exceptions:
#       - Internal
#               - When session file cannot be opened to write
sub _savesession
{
    my ($user, $passwd, $sid, $key) = @_;

    if(not defined($sid)) {
        my $rndStr;
        for my $i (1..64) {
            $rndStr .= rand (2**32);
        }

        my $md5 = Digest::MD5->new();
        $md5->add($rndStr);
        $sid = $md5->hexdigest();

        for my $i (1..64) {
            $rndStr .= rand (2**32);
        }
        $md5 = Digest::MD5->new();
        $md5->add($rndStr);

        $key = $md5->hexdigest();
    }

    my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_CBC());

    my $len = length($passwd);
    my $newlen = (int(($len-1)/16) + 1) * 16;

    $passwd = $passwd . ("\0" x ($newlen - $len));

    my $cryptedpass = $cipher->encrypt($passwd);
    my $encodedcryptedpass = MIME::Base64::encode($cryptedpass, '');
    my $sidFile;
    my $filename = EBox::MailFilterUI::usersessiondir() . $user;
    unless  ( open ( $sidFile, '>', $filename )){
        throw EBox::Exceptions::Internal(
                "Could not open to write ".  $filename);
    }
    # Lock the file in exclusive mode
    flock($sidFile, LOCK_EX)
        or throw EBox::Exceptions::Lock('EBox::MailFilterUI::Auth');
    # Truncate the file after locking
    truncate($sidFile, 0);
    if (defined $sid) {
       my $cookie = join("\t", $sid, $encodedcryptedpass, time());
       print $sidFile $cookie;
    }
    # Release the lock
    flock($sidFile, LOCK_UN);
    close($sidFile);

    return $sid . $key;
}

sub _updatesession
{
    my ($user) = @_;

    my $sidFile;
    my $sess_file = EBox::MailFilterUI::usersessiondir() . $user;
    unless (open ($sidFile, '+<', $sess_file)) {
        throw EBox::Exceptions::Internal("Could not open $sess_file");
    }
    # Lock in exclusive
    flock($sidFile, LOCK_EX)
        or throw EBox::Exceptions::Lock('EBox::MailFilterUI::Auth');

    my $sess_info = <$sidFile>;
    my ($sid, $cryptedpass, $lastime);
    ($sid, $cryptedpass, $lastime) = split (/\t/, $sess_info) if defined $sess_info;

    # Truncate the file
    truncate($sidFile, 0);
    seek($sidFile, 0, 0);
    print $sidFile $sid . "\t" . $cryptedpass . "\t" . time if defined $sid;
    # Release the lock
    flock($sidFile, LOCK_UN);
    close($sidFile);
}


# Method: checkPassword
#
#
#
# Parameters:
#
#       user - string containing the user name
#       passwd - string containing the plain password
#
# Returns:
#
#       mail of the authorized user or undef if auth failed
#
# Exceptions:
#
#       <EBox::Exceptions::Internal> - when password's file cannot be opened
sub checkPasswordAndGetMail # (user, password)
{
    my ($class, $user, $passwd) = @_;
    my $CONF_FILE = EBox::MailFilterUI->LDAP_CONF;

     my $url;
     try {
       $url = EBox::Config::configkeyFromFile('ldap_url', $CONF_FILE);
     } otherwise {};

     if (not $url) {
      # no auth possible
      return 0;
    }

    my $ldap = $class->_checkLdapConn($user, $passwd, $url);
    if (not $ldap){
        return 0;
    }

    # XXX add exception/error handling
    # get base DN
    my $result = $ldap->search(
         'base' => '',
         'scope' => 'base',
         'filter' => '(objectclass=*)',
         'attrs' => ['defaultNamingContext']
     );
    my $entry = ($result->entries)[0];
    my $baseDN = $entry->get_value('defaultNamingContext');

    # get user mail
    $result = $ldap->search(
        base => $baseDN,
        filter => "&(objectClass=person)(userPrincipalName=$user)",
        scope => 'sub',
        attrs => ['mail'],
       );
    $entry =  ($result->entries)[0];

    # get mail
    my $mail = $entry->get_value('mail');
    return $mail;
}

# for now we only support AD-style login
sub _checkLdapConn
{
    my ($class, $user, $password, $url) = @_;
    my $ldap  = undef;
    try {
        $ldap = EBox::Ldap::safeConnect($url);
        EBox::Ldap::safeBind($ldap, $user, $password);
    } otherwise {
        $ldap = undef; # auth failed
    };

    return $ldap;
}



# Method: updatePassword
#
#   Updates the current session information with the new password
#
# Parameters:
#
#       passwd - string containing the plain password
#
sub updatePassword
{
    my ($class, $user, $passwd) = @_;
    my $r = Apache2::RequestUtil->request();

    my $session_info = EBox::MailFilterUI::Auth->key($r);
    my $sid = substr($session_info, 0, 32);
    my $key = substr($session_info, 32, 32);
    _savesession($user, $passwd, $sid, $key);
}

# Method: authen_cred
#
#       Overriden method from <Apache2::AuthCookie>.
#
sub authen_cred  # (request, user, password)
{
    my ($class, $r, $user, $passwd) = @_;

    my $mail = $class->checkPasswordAndGetMail($user, $passwd);
    unless ($mail) {
        EBox::initLogger('mfui-log.conf');
        my $log = EBox->logger();
        my $ip  = $r->connection->remote_host();
        $log->warn("Failed login from: $ip");
        return;
    }

    return _savesession($user, $passwd, undef, undef);
}

# Method: credentials
#
#   gets the current user and password
#
sub credentials
{
    my $r = Apache2::RequestUtil->request();

    my $user = $r->user();

    my $session_info = EBox::MailFilterUI::Auth->key($r);
    return _credentials($user, $session_info);
}

sub _credentials
{
    my ($user, $session_info) = @_;

    my $key = substr($session_info, 32, 32);

    my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_CBC());

    my $SID_F;
    my $sess_file  = EBox::MailFilterUI::usersessiondir() . $user;
    unless (open ($SID_F,  '<', $sess_file)) {
        throw EBox::Exceptions::Internal("Could not open $sess_file");
    }
    # Lock in shared mode for reading
    flock($SID_F, LOCK_SH)
        or throw EBox::Exceptions::Lock('EBox::MailFilterUI::Auth');

    my $sess_info = <$SID_F>;
    my ($sid, $cryptedpass, $lastime);
    ($sid, $cryptedpass, $lastime) = split (/\t/, $sess_info) if defined $sess_info;

    # Release the lock
    flock($SID_F, LOCK_UN);
    close($SID_F);

    my $decodedcryptedpass = MIME::Base64::decode($cryptedpass);
    my $pass = $cipher->decrypt($decodedcryptedpass);
    $pass =~ tr/\x00//d;

    return { 'user' => $user, 'pass' => $pass };
}

# Method: authen_ses_key
#
#   Overriden method from <Apache2::AuthCookie>.
#
sub authen_ses_key  # (request, session_key)
{
    my ($class, $r, $session_data) = @_;

    my $session_key = substr($session_data, 0, 32);

    my $SID_F; # sid file handle

    my $user = undef;
    my $expired;

    for my $sess_file (glob(EBox::MailFilterUI::usersessiondir() . '*')) {
        unless (open ($SID_F,  '<', $sess_file)) {
            EBox::error("Could not open '$sess_file|'");
            next;
        }
        # Lock in shared mode for reading
        flock($SID_F, LOCK_SH)
          or throw EBox::Exceptions::Lock('EBox::MailFilterUI::Auth');

        my $sess_info = <$SID_F>;
        my ($sid, $cryptedpass, $lastime);
        ($sid, $cryptedpass, $lastime) = split (/\t/, $sess_info) if defined $sess_info;

        $expired = _timeExpired($lastime);
        if ($session_key eq $sid) {
            $user = basename($sess_file);
        }

        # Release the lock
        flock($SID_F, LOCK_UN);
        close($SID_F);

        defined($user) and last;
    }
    if(defined($user) and !$expired) {
        my $ldap = EBox::Ldap->instance();
        $ldap->refreshLdap();
        _updatesession($user);
        return $user;
    } elsif (defined($user) and $expired) {
        $r->subprocess_env(LoginReason => "Expired");
        unlink(EBox::MailFilterUI::usersessiondir() . $user);
    } else {
        $r->subprocess_env(LoginReason => "NotLoggedIn");
    }

    return;
}

sub _timeExpired
{
    my ($lastime) = @_;

    my $expires = $lastime + EXPIRE;

    my $expired = (time() > $expires);
    return $expired;
}

# Method: logout
#
#   Overriden method from <Apache2::AuthCookie>.
#
sub logout # (request)
{
    my ($class, $r) = @_;

    my $filename = EBox::MailFilterUI::usersessiondir() . $r->user;
    unlink($filename);

    $class->SUPER::logout($r);
}

1;
