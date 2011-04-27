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
  
  unshift(@_, "_") if (@_ == 1);
  
  my @keys;
  my $template = "(";
  while (@_) {
    push(@keys, shift());
    $template .= shift();
  }
  $template .= ")<";
  
  my $buf;
  if (ref $fh) {
    my $len = _sizeof($template);
    _dbg("%s: read (%d): %s", $where, $len, $template);
    if (read($fh, $buf, $len) != $len) {
      return _err($errstr, "read(): %s: expected %d bytes (%s)",
        $where,
        $len,
        $template,
      );
    }
    _dbg(" -> %s", unpack("h" . $len * 2, $buf)) if $debug;
  }
  else {
    _dbg("%s: read (buf): %s", $where, $template);
    $buf = $fh;
    _dbg(" -> %s", unpack("h*", $buf)) if $debug;
  }
  
  my %buf;
  @buf{@keys} = unpack($template, $buf);
  _dbg(" -> { %s }", join ", " => map { sprintf("%s => %s", $_ , $buf{$_} // "undef") } @keys) if $debug;
  
  if (@keys == 1) {
    return $buf{_} if $keys[0] eq "_";
  }
  delete $buf{_};
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
  binmode($file) // return _err($errstr, "binmode(): %s", $!);

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
  ) // return;

  _expect($errstr, "header/magic", "%08x",
    $header->{magic},
    ord("L")
  ) // return;
  # Yes, these are the same:
  #   "01140200-0000-0000-c000-000000000046"
  #   {00021401-0000-0000-C000-000000000046} (cf. [MS-SHLLINK] 2.1)
  # Somebody please shoot the guy who invented the CLSID/GUID format
  # with its mixture of native and binary representation.
  # http://msdn.microsoft.com/en-us/library/aa373931.aspx
  _expect($errstr, "header/clsid", "%s",
    $header->{clsid},
    join("", qw(01140200 0000 0000 c000 000000000046))
  ) // return;

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
  
  # [MS-SHLLINK] 2.2
  if ($header->{flags}->{has_link_target}) {
    my $len = _read_and_unpack($file, "link_target/size", "S") // return;
    
    # [MS-SHLLINK] 2.2.2
    while (1) {
      $len = _read_and_unpack($file, "link_target/item/size", "S") // return;
      
      # [MS-SHLLINK] 2.2.1
      last unless $len;
      
      # [MS-SHLLINK] 2.2.2
      $len -= _sizeof("S");
      
      # Skip item, we don't know how to parse it.
      # TODO: Find out...
      _read_and_unpack($file, "link_target/item/skip", skip => "x[$len]") // return;
    }
  }
  
  # [MS-SHLLINK] 2.3
  if ($header->{flags}->{has_link_info}) {
    my $len = _read_and_unpack($file, "link_info/size", "L") // return;
    $len -= _sizeof("L");

    # [MS-SHLLINK] 2.1.1
    if ($header->{flags}->{force_no_link_info}) {
      _read_and_unpack($file, "link_info/skip", skip => "x[$len]") // return;
    }
    else {
      # [MS-SHLLINK] 2.3
      my $hlen = _read_and_unpack($file, "link_info/head/size", "L") // return;
      $len -= $hlen - _sizeof("L");
      
      my $flags = _read_and_unpack($file, "link_info/head/flags", "L") // return;
      $flags = _map_bits($flags, qw(
        volume_id_and_local_base_path
        common_network_relative_link_and_path_suffix
      ));
      
      my $data = _read_and_unpack($file, "link_info/head/offsets",
        volume_id                    => "L",
        local_base_path              => "L",
        common_network_relative_link => "L",
        common_path_suffix           => "L",
        local_base_path_unicode      => "L" . ($hlen >= 0x24)*1,
        common_path_suffix_unicode   => "L" . ($hlen >= 0x24)*1,
        _                            => "x" . eval {
          my $xlen = $hlen;
          $xlen -= _sizeof("L3L4L2");
          $xlen += _sizeof("L2") if $xlen < 0;
          return $xlen;
        }
      ) // return;
      
      unless ($flags->{volume_id_and_local_base_path}) {
        delete @{$data}{qw(
          volume_id
          local_base_path
          local_base_path_unicode
        )};
      }
      unless ($flags->{common_network_relative_link_and_path_suffix}) {
        delete @{$data}{qw(
          common_network_relative_link
        )};
      }
      
      foreach my $key (keys %{$data}) {
        unless (defined $data->{$key}) {
          delete $data->{$key};
          next;
        }
        
        $data->{$key} -= $hlen;
        _dbg("link_info/$key: offset %d", $data->{$key});
        if ($data->{$key} < 0) {
          return _err($errstr, "link_info/head: malformed offset for $key");
        }
      }
      
      my $buf = _read_and_unpack($file, "link_info/data", "a[$len]") // return;
      
      # [MS-SHLLINK] 2.3.1
      if (defined $data->{volume_id}) {
        my $offset = $data->{volume_id};
        my $size = _read_and_unpack($buf, "link_info/data/volume_id/size",
          "x[$offset]L"
        );
          
        my $buf = _read_and_unpack($buf, "link_info/data/volume_id",
          "x[$offset]x[L]a[$size]");
        my $volume = _read_and_unpack($buf, "link_info/data/volume_id/head",
          drive_type          => "L",
          drive_serial_number => "L",
          volume_label_offset => "L",
        );
        
        $offset = delete $volume->{volume_label_offset};
        if ($offset != 0x14) {
          $offset -= _sizeof("L");
          $volume->{volume_label} = _read_and_unpack($buf, "link_info/data/volume_id",
            "x[$offset]Z*"
          );
        }
        else {
          $offset = _read_and_unpack($buf, "link_info/data/volume_id/volume_label_unicode_offset",
            "x[L4]L"
          );
          $offset -= _sizeof("L");
          my $len = index($buf, "\0\0", $offset) - $offset + 1;
          $volume->{volume_label} = decode('utf-16le', _read_and_unpack($buf, "link_info/data/volume_id/volume_label_unicode",
            "x[$offset]a[$len]"
          ));
        }
        
        $volume->{drive_type} = eval { given ($volume->{drive_type}) {
          when (0) { return "unknown" }
          when (1) { return "no_root_dir" }
          when (2) { return "removable" }
          when (3) { return "fixed" }
          when (4) { return "remote" }
          when (5) { return "cdrom" }
          when (6) { return "ramdisk" }
          default  { return $volume->{drive_type} }
        }};
      }
      
      foreach my $key (qw(
        common_path_suffix
        local_base_path
      )) {
        next unless defined $data->{$key};
        my $offset = $data->{$key};
        $data->{$key} = _read_and_unpack($buf, "link_info/data/$key",
          "x[$offset]Z*");
      }
    }
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
      my $len = _read_and_unpack($file, "$key/size", "S") // return;
      next unless $len;
      
      # [MS-SHLLINK] 2.1.1; http://msdn.microsoft.com/en-us/library/dd374081.aspx
      $len *= 2 if $header->{flags}->{is_unicode};
      my $str = _read_and_unpack($file, "$key/data", "a[$len]") // return;
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
