package File::Shortcut;

use 5.10.0;

use warnings;
use strict;

use parent qw(Exporter);
our @EXPORT_OK = qw(
  shortcut
  readshortcut
);

use Carp;


=head1 NAME

File::Shortcut - Read and write Windows shortcut files (C<*.lnk>).

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    use File::Shortcut qw(shortcut readshortcut);

    shortcut "C:\\WINDOWS\\notepad.exe", "notepad.exe.lnk", {
      description => "The worst editor on earth",
    } or die $File::Shortcut::errstr;

    my $path = readshortcut("notepad.exe.lnk") or die $File::Shortcut::errstr;


=head1 EXPORT

The following functions can be imported into your script:

    shortcut
    readshortcut


=head1 SUBROUTINES/METHODS

=cut

our $errstr = "";

sub _err {
  my($errstr) = shift;
  local $SIG{__WARN__} = \&confess;
  $$errstr = sprintf(shift, @_);
  return undef;
}

sub _expect {
  my($errstr, $where, $format, $value, $expect) = @_;
  return 1 if $value ~~ $expect;
  return _err($errstr, "$where: expected $format, got $format",
    $expect,
    $value,
  );
}


sub _sizeof {
  my $type = shift;
  return length(pack("x[$type]"));
}

sub _read_and_unpack {
  my($fh, $where) = (shift, shift);
  
  my @keys;
  my $len = 0;
  my $template = "(";
  while (@_) {
    my($key, $t) = (shift, shift);
    push(@keys, $key);
    $template .= $t;
    $len += _sizeof($t);
  }
  $template .= ")<";
  
  my $buf;
  if (read($fh, $buf, $len) != $len) {
    return _err($errstr, "read(): %s: expected %d bytes (%s)",
      $where,
      $len,
      $template,
    );
  }
  
  my %buf;
  @buf{@keys} = unpack($template, $buf);
  return \%buf;
}


sub _bit_is_set {
  my($value, $bit) = @_;
  return $value & (1 << $bit) ? 1 : 0;
}


=head2 readshortcut EXPR

=head2 readshortcut

Returns the value of a shortcut.  If there is some system error, returns 
the undefined value and sets C<$File::Shortcut::errstr> (and probably also
C<$!> (errno)).  EXPR can be either a string representing a file path
or a file handle.  B<In the latter case, binmode is set on that file
handle.>  If EXPR is omitted, uses C<$_>.

=cut

sub readshortcut {
  my $file = @_ ? $_[0] : $_;
  return _readshortcut(\$errstr, $file);
}

sub _readshortcut {
  my($errstr, $file) = @_;

  if (ref $file) {
    croak "parameter must be a file handle (or path)" if tell $file == -1;
  }
  else {
    open my $fh, '<', $file or return _err($errstr, "open(%s): %s", $file, $!);
    $file = $fh;
  }
  binmode($file) or return _err($errstr, "binmode(): %s", $!);

  my $header = _read_and_unpack($file, "header",
    magic    => "L",   #  4 bytes Always 4C 00 00 00 ("L")
    guid     => "h32", # 16 bytes GUID for shortcut files
    flags    => "L",   #  1 dword Shortcut flags
    attribs  => "L",   #  1 dword Target file flags
    ctime    => "Q",   #  1 qword Creation time
    atime    => "Q",   #  1 qword Last access time
    mtime    => "Q",   #  1 qword Modification time
    fsize    => "L",   #  1 dword File length
    icon     => "L",   #  1 dword Icon number
    show     => "L",   #  1 dword Show Window
    hotkey   => "L",   #  1 dword Hot Key
    reserved => "L",   #  1 dword Reserved
    reserved => "L",   #  1 dword Reserved
  ) or return;
  delete $header->{reserved};

  _expect($errstr, "header: magic", "%08x",
    $header->{magic},
    ord("L"));
  _expect($errstr, "header: guid", "%s",
    $header->{guid},
    "01140200000000c00000000046");

  $header->{flags} = {
    _raw        => $header->{flags},
    idlist      => _bit_is_set($header->{flags},  0),
    fod         => _bit_is_set($header->{flags},  1),
    description => _bit_is_set($header->{flags},  2),
    relative    => _bit_is_set($header->{flags},  3),
    workdir     => _bit_is_set($header->{flags},  4),
    args        => _bit_is_set($header->{flags},  5),
    icon        => _bit_is_set($header->{flags},  6),
  };
  $header->{attribs} = {
    _raw       => $header->{attribs},
    readonly   => _bit_is_set($header->{attribs},  0),
    hidden     => _bit_is_set($header->{attribs},  1),
    system     => _bit_is_set($header->{attribs},  2),
    volume     => _bit_is_set($header->{attribs},  3),
    dir        => _bit_is_set($header->{attribs},  4),
    archive    => _bit_is_set($header->{attribs},  5),
    encrypted  => _bit_is_set($header->{attribs},  6),
    normal     => _bit_is_set($header->{attribs},  7),
    temp       => _bit_is_set($header->{attribs},  8),
    sparse     => _bit_is_set($header->{attribs},  9),
    reparse    => _bit_is_set($header->{attribs}, 10),
    compressed => _bit_is_set($header->{attribs}, 11),
    offline    => _bit_is_set($header->{attribs}, 12),
  };
  
  $header->{show} = eval { given ($header->{show}) {
    when ( 1) { return "normal" };
    when ( 2) { return "minimized" };
    when ( 3) { return "maximized" };
    default   { return $header->{show} };
  }};

  my %struct = (
    header => $header,
  );
  
  if ($header->{flags}->{idlist}) {
    my $len = _read_and_unpack($file, "idlist", _ => "S") or return;
    $len = $len->{_};

    while (1) {
      $len = _read_and_unpack($file, "idlist", _ => "L") or return;
      $len = $len->{_};
      last if ($len == 0);
      $len -= _sizeof("L");
      
      my $data = _read_and_unpack($file, "idlist",
        len      => "L",
        offset   => "L", 
        remote   => "L",
        volinfo  => "L",
        basepath => "L",
        netvol   => "L",
        path     => "L",
      ) or return;
      if ($data->{remote} > 1) {
        # error
      }
      
      # TODO
    }
  }

  foreach my $key (qw(
    description
    relative
    workdir
    args
    icon
  )) {
    if ($header->{flags}->{$key}) {
      my $len = _read_and_unpack($file, $key, _ => "S") or return;
      $len = $len->{_};
      next unless $len;
      my $str = _read_and_unpack($file, $key, _ => "a$len") or return;
      $struct{$key} = $str->{_};
    }
  }

  return \%struct;
}


=head2 shortcut OLDFILE, NEWFILE, METADATA

=head2 shortcut OLDFILE, NEWFILE

Creates a new filename linked to the old filename.  Returns true for
success, false otherwise.

Optionally, a METADATA hash can be used to set further values of the 
shortcut file.  TODO: format

=cut

sub shortcut {
  
}


=head1 AUTHOR

Malte S. Stretz, C<< <mss at apache.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-file-shortcut at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-Shortcut>.
I will be notified, and then you'll automatically be notified of progress on 
your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::Shortcut


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-Shortcut>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-Shortcut>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-Shortcut>

=item * Search CPAN

L<http://search.cpan.org/dist/File-Shortcut/>

=back


=head1 ACKNOWLEDGEMENTS

This module is heavily based on the information found at the following links:

=over 4

=item * Jesse Hager: "The Windows Shortcut File Format"

L<http://8bits.googlecode.com/files/The_Windows_Shortcut_File_Format.pdf>

=item * Daniel at Stdlib.com: "Shortcut File Format (.lnk)"

L<http://www.stdlib.com/art6-Shortcut-File-Format-lnk.html>

=back


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Malte S. Stretz.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of File::Shortcut
