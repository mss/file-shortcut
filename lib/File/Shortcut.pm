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

use Encode;


=head1 NAME

File::Shortcut - Read and write Windows shortcut files (C<*.lnk>).

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    use File::Shortcut qw(shortcut readshortcut);
    use File::Spec::Win32;

    shortcut "C:\\WINDOWS\\notepad.exe", "notepad.exe.lnk", {
      description => "The worst editor on earth",
    } or die $File::Shortcut::errstr;

    my $path = readshortcut("notepad.exe.lnk") or die $File::Shortcut::errstr;
    my($vol, $dir, $file) = File::Spec::Win32->splitpath($path);


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
  return 1 if ($value ~~ $expect);
  return _err($errstr, "%s: expected $format, got $format",
    $where,
    $expect,
    $value,
  );
}

our $debug = 0;

sub _dbg {
  return unless $debug;
  my $fh = ref $debug ? $debug : \*STDERR;
  printf $fh shift() . "\n", @_;
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
  
  _dbg("%s: read %s %d: %s", $fh, $where, $len, $template);
  my $buf;
  if (read($fh, $buf, $len) != $len) {
    return _err($errstr, "read(): %s: expected %d bytes (%s)",
      $where,
      $len,
      $template,
    );
  }
  _dbg("%s: -> %s", $fh, unpack("h" . $len * 2, $buf)) if $debug;
  
  my %buf;
  @buf{@keys} = unpack($template, $buf);
  _dbg("%s: -> { %s }", $fh, join ", " => map { sprintf("%s => %s", $_ , $buf{$_} // "undef") } @keys) if $debug;
  return \%buf;
}


sub _map_bits {
  my $value = shift;
  
  my %result = (
    _raw => $value,
  );
  
  while (@_) {
    my $key = shift;
    next unless $key;
    $result{$key} = $value & 1;
    $value >>= 1;
  }
  
  return \%result;
}


sub _parse_filetime {
  # Windows epoch: 1601-01-01.  Precision: 100ns
  # http://msdn.microsoft.com/en-us/library/ms724284.aspx
  # Loosely based on
  #  * DateTime::Format::WindowsFileTime 0.02
  #  * http://www.perlmonks.org/?node_id=846055
  #  * http://stackoverflow.com/questions/1864245/how-can-i-do-64-bit-arithmetic-in-perl
  use bignum;
  
  my $value = shift;
  
  my($lo, $hi) = unpack 'VV' => $value;
  $value = $hi * 2**32 + $lo;
  
  # Fix the epoch.
  $value -= 11644473600 * 1e7;
  # Centi-nanoseconds to seconds.
  $value /= 1e7;

  no bignum;
  return $value->bstr() * 1;
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

  # [MS-SHLLINK] 2.1
  my $header = _read_and_unpack($file, "header",
    magic    => "L",   #  4 bytes Always 4C 00 00 00 ("L")
    clsid    => "H32", # 16 bytes GUID for shortcut files
    flags    => "L",   #  1 dword Shortcut flags
    attrs    => "L",   #  1 dword Target file flags
    ctime    => "a[Q]",#  1 qword Creation time
    atime    => "a[Q]",#  1 qword Last access time
    mtime    => "a[Q]",#  1 qword Modification time
    fsize    => "L",   #  1 dword File length
    icon     => "L",   #  1 dword Icon index
    show     => "L",   #  1 dword Show command
    hotkey   => "S",   #  1  word Hot Key
    _        => "S",   #  1  word Reserved
    _        => "L",   #  1 dword Reserved
    _        => "L",   #  1 dword Reserved
  ) or return;
  delete $header->{_};

  _expect($errstr, "header/magic", "%08x",
    $header->{magic},
    ord("L")
  ) or return;
  # Yes, these are the same:
  #   "01140200-0000-0000-c000-000000000046"
  #   {00021401-0000-0000-C000-000000000046} (cf. [MS-SHLLINK] 2.1)
  # Somebody please shoot the guy who invented the CLSID/GUID format
  # with its mixture of native and binary representation.
  # http://msdn.microsoft.com/en-us/library/aa373931.aspx
  _expect($errstr, "header/clsid", "%s",
    $header->{clsid},
    join("", qw(01140200 0000 0000 c000 000000000046))
  ) or return;

  my %struct = (
    header => $header,
  );
  
  # [MS-SHLLINK] 2.1.1
  $header->{flags} = _map_bits($header->{flags}, qw(
    has_link_target
    has_link_info
    has_name
    has_relative_path
    has_working_dir
    has_arguments
    has_icon_location
    is_unicode
    force_no_link_info
    has_exp_string
    run_in_separate_process
    _
    has_darwin_id
    run_as_user
    has_exp_icon
    no_pidl_alias
    _
    run_with_shim_layer
    force_no_link_track
    enable_target_metadata
    disable_link_path_tracking
    disable_known_folder_alias
    allow_link_to_link
    unalias_on_save
    prefer_environment_path
    keep_local_id_list_for_unc_target
  ));
  delete $header->{flags}->{_};
  
  # [MS-SHLLINK] 2.2
  if ($header->{flags}->{has_link_target}) {
    my $len = _read_and_unpack($file, "link_target/size", _ => "S") or return;
    $len = $len->{_};
    
    # [MS-SHLLINK] 2.2.2
    while (1) {
      $len = _read_and_unpack($file, "link_target/item/size", _ => "S") or return;
      $len = $len->{_};
      
      # [MS-SHLLINK] 2.2.1
      last unless $len;
      
      # [MS-SHLLINK] 2.2.2
      $len -= _sizeof("S");
      
      # Skip item, we don't know how to parse it.
      # TODO: Find out...
      _read_and_unpack($file, "link_target/item/skip", _ => "x$len") or return;
    }
  }
  
  my $len = _read_and_unpack($file, "link_info/size", _ => "L") or return;
  $len = $len->{_};
  unless ($header->{flags}->{has_link_info}) {
    _read_and_unpack($file, "link_info/skip", _ => "x$len") or return;
  }
  else {
    my $data = _read_and_unpack($file, "link_info/head",
      pnext    => "L",
      flags    => "L",
      pvol     => "L",
      pbase    => "L",
      pnet     => "L",
      ppath    => "L",
    ) or return;
    $data->{flags} = _map_bits($data->{flags}, qw(
      local
      remote
    ));
    
    # TODO: Don't skip
    _read_and_unpack($file, "link_info/skip", _ => "x" . ($len - _sizeof("L7"))) or return;
  }

  # [MS-SHLLINK] 2.4
  foreach my $key (qw(
    name
    relative_path
    working_dir
    arguments
    icon_location
  )) {
    if ($header->{flags}->{"has_$key"}) {
      my $len = _read_and_unpack($file, "$key/size", _ => "S") or return;
      $len = $len->{_};
      next unless $len;
      
      # [MS-SHLLINK] 2.1.1; http://msdn.microsoft.com/en-us/library/dd374081.aspx
      $len *= 2 if $header->{flags}->{is_unicode};
      my $str = _read_and_unpack($file, "$key/data", _ => "a$len") or return;
      $str = $str->{_};
      $str = decode('utf-16le', $str) if $header->{flags}->{is_unicode};
      
      $struct{$key} = $str;
    }
  }
  # TODO: delete $header->{flags};
  
  # [MS-SHLLINK] 2.1.2
  $header->{attrs} = _map_bits($header->{attrs}, qw(
    readonly
    hidden
    system
    _
    directory
    archive
    _
    normal
    temporary
    sparse_file
    reparse_point
    compressed
    offline
    not_content_indexed
    encrypted
  ));
  delete $header->{attrs}->{_};
  
  # Parse 64-bit FileTime.
  for my $key (qw(ctime atime mtime)) {
    $header->{$key} = _parse_filetime($header->{$key});
  }
  
  # [MS-SHLLINK] 2.1
  $header->{show} = eval { given ($header->{show}) {
    when (1) { return "normal" };
    when (3) { return "maximized" };
    when (7) { return "minimized" };
    default  { return "normal" };
  }};
  
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

=item * [MS-SHLLINK] Microsoft: "Shell Link (.LNK) Binary File Format"

L<http://msdn.microsoft.com/en-us/library/dd871305.aspx>

=item * [HAGER1998] Jesse Hager: "The Windows Shortcut File Format"

L<http://8bits.googlecode.com/files/The_Windows_Shortcut_File_Format.pdf>

=item * [STDLIB2007] Daniel at Stdlib.com: "Shortcut File Format (.lnk)"

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
