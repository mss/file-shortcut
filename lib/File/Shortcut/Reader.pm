package File::Shortcut::Reader;

use 5.10.0;

use warnings;
use strict;

use Carp;

use Encode;

use File::Shortcut;
use File::Shortcut::Util qw(
  err expect dbg
  sizeof
  unpack_bits unpack_index
  parse_filetime
);
use File::Shortcut::Data;


sub read_shortcut {
  my($fh) = @_;
  my $dbg = $File::Shortcut::Debug;

  # [MS-SHLLINK] 2.1
  my $header = read_and_unpack($fh, "header",
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
  );

  # The magic string is officially the size of the header.  They had to insert
  # three reserved (aka must be zero) fields to play this pun.  Go figure...
  expect("header/magic", "%08x",
    $header->{magic},
    ord("L")
  );
  # Yes, these are the same:
  #   "01140200-0000-0000-c000-000000000046"
  #   {00021401-0000-0000-C000-000000000046} (cf. [MS-SHLLINK] 2.1)
  # Somebody please shoot the guy who invented the CLSID/GUID format
  # with its mixture of native and binary representation.
  # http://msdn.microsoft.com/en-us/library/aa373931.aspx
  expect("header/clsid", "%s",
    $header->{clsid},
    join("", qw(01140200 0000 0000 c000 000000000046))
  );

  $header->{flags} = unpack_bits($header->{flags},
    @File::Shortcut::Data::HEADER_FLAGS
  );
  dbg("header/flags/%s: %d", $header->{flags});

  # Map the file attributes.
  $header->{attrs} = unpack_bits($header->{attrs},
    @File::Shortcut::Data::FILE_ATTRIBUTES
  );

  # Parse 64-bit FileTime.
  for my $key (qw(ctime atime mtime)) {
    $header->{$key} = parse_filetime($header->{$key});
  }

  # Map the requested window state [MS-SHLLINK] 2.1
  $header->{show} = unpack_index($header->{show}, 1,
    @File::Shortcut::Data::SHOW_COMMAND
  );

  # We don't want to return these.
  my $flags = delete $header->{flags};

  # Parse and return the rest of the file.
  return {
    header => $header,
    read_link_target($fh, $flags),
    read_link_info($fh, $flags),
    read_string_data($fh, $flags),
  };
}

sub read_link_target {
  my($fh, $flags) = @_;
  my %result;

  # [MS-SHLLINK] 2.2
  if ($flags->{has_link_target}) {
    my $len = read_and_unpack($fh, "link_target/size", "S");

    # [MS-SHLLINK] 2.2.2
    while (1) {
      $len = read_and_unpack($fh, "link_target/item/size", "S");

      # [MS-SHLLINK] 2.2.1
      last unless $len;

      # [MS-SHLLINK] 2.2.2
      $len -= sizeof("S");

      # Skip item, we don't know how to parse it.
      # TODO: Find out...
      read_and_unpack($fh, "link_target/item/skip", skip => "x[$len]");
    }
  }

  return %result;
}

sub read_link_info {
  my($fh, $flags) = @_;
  my %result;

  # [MS-SHLLINK] 2.3
  if ($flags->{has_link_info}) {
    my $len = read_and_unpack($fh, "link_info/size", "L");
    $len -= sizeof("L");

    # [MS-SHLLINK] 2.1.1
    if ($flags->{force_no_link_info}) {
      read_and_unpack($fh, "link_info/skip", skip => "x[$len]");
    }
    else {
      # [MS-SHLLINK] 2.3
      my $hlen = read_and_unpack($fh, "link_info/head/size", "L");
      $len -= $hlen - sizeof("L");

      my $flags = unpack_bits(read_and_unpack($fh, "link_info/head/flags", "L"),
        @File::Shortcut::Data::LINK_INFO_FLAGS
      );
      dbg("link_info/head/flags/%s: %d", $flags);

      my $data = read_and_unpack($fh, "link_info/head/offsets",
        volume_id                    => "L",
        local_base_path              => "L",
        common_network_relative_link => "L",
        common_path_suffix           => "L",
        local_base_path_unicode      => "L" . ($hlen >= 0x24)*1,
        common_path_suffix_unicode   => "L" . ($hlen >= 0x24)*1,
        _                            => "x" . eval {
          my $xlen = $hlen;
          $xlen -= sizeof("L3L4L2");
          $xlen += sizeof("L2") if $xlen < 0;
          return $xlen;
        }
      );

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
        dbg("link_info/$key: offset %d", $data->{$key});
        if ($data->{$key} < 0) {
          return err("link_info/head: malformed offset for $key");
        }
      }

      # Slurp the whole struct so we can jump around freely.
      my $buf = read_and_unpack($fh, "link_info/data", "a[$len]");

      # These are easy as they are just zero-terminated strings.
      foreach my $key (qw(
        common_path_suffix
        local_base_path
      )) {
        next unless defined $data->{$key};
        my $offset = $data->{$key};
        $data->{$key} = read_and_unpack_asciz($buf, "link_info/data/$key",
          $offset
        );
      }

      # [MS-SHLLINK] 2.3.1
      if (defined $data->{volume_id}) {
        my $offset = $data->{volume_id};
        my $buf = read_and_unpack($buf, "link_info/data/volume_id",
          "x[$offset]L/a");
        my $volume = read_and_unpack($buf, "link_info/data/volume_id/head",
          drive_type                  => "L",
          drive_serial_number         => "L",
          volume_label_offset         => "L",
          volume_label_unicode_offset => "L" . (length($buf) >= sizeof("L4"))*1,
        );

        # "If the value of this field is 0x00000014, it MUST be ignored,
        # and the value of the VolumeLabelOffsetUnicode field MUST be used 
        # to locate the volume label string."
        $offset = delete $volume->{volume_label_offset};
        if ($offset != 0x14) {
          # The buffer doesn't contain the size field, so subtract it from
          # the offset.
          $offset -= sizeof("L");
          # This is a plain zero-terminated ASCII string.
          $volume->{volume_label} = read_and_unpack_asciz($buf, "link_info/data/volume_id",
            $offset
          );
          # Remove the unused field.
          delete $volume->{volume_label_unicode_offset}
        }
        else {
          $offset = delete $volume->{volume_label_unicode_offset};
          # The buffer doesn't contain the size field, so subtract it from
          # the offset.
          $offset -= sizeof("L");
          # This is a zero-terminated UTF-16 string.
          $volume->{volume_label} = read_and_unpack_utf16z($buf, "link_info/data/volume_id/volume_label_unicode",
            $offset
          );
        }

        # Map the drive types, defaulting to unknown.
        $volume->{drive_type} = unpack_index($volume->{drive_type}, 0,
          @File::Shortcut::Data::DRIVE_TYPE
        );

        $result{volume_id} = $volume;
      }

      
    }
  }

  return %result;
}

sub read_string_data {
  my($fh, $flags) = @_;
  my %result;

  # [MS-SHLLINK] 2.4
  foreach my $key (qw(
    name
    relative_path
    working_dir
    arguments
    icon_location
  )) {
    if ($flags->{"has_$key"}) {
      my $len = read_and_unpack($fh, "$key/size", "S");
      next unless $len;

      # [MS-SHLLINK] 2.1.1
      $result{$key} = read_and_unpack_str($fh, "$key/data",
        0, $len,
        $flags->{is_unicode}
      );
    }
  }

  return %result;
}


sub read_and_unpack {
  my($fh, $where) = (shift, shift);
  my $dbg = $File::Shortcut::Debug;

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
    my $len = sizeof($template);
    dbg("%s: read (%d): %s", $where, $len, $template);
    if (read($fh, $buf, $len) != $len) {
      return err("read(): %s: expected %d bytes (%s)",
        $where,
        $len,
        $template,
      );
    }
    dbg(" -> %s", unpack("h" . $len * 2, $buf)) if $dbg;
  }
  else {
    dbg("%s: read (buf): %s", $where, $template);
    $buf = $fh;
    dbg(" -> %s", unpack("h*", $buf)) if $dbg;
  }

  my %buf;
  @buf{@keys} = unpack($template, $buf);
  dbg(" -> { %s }", join ", " => map { sprintf("%s => %s", $_ , $buf{$_} // "undef") } @keys) if $dbg;

  if (@keys == 1) {
    return $buf{_} if $keys[0] eq "_";
  }
  delete $buf{_};
  return \%buf;
}

sub read_and_unpack_str {
  my($fh, $where, $offset, $len, $utf16) = @_;
  $offset //= 0;
  $len    //= 0;
  $utf16  //= 0;

  # Microsoft likes to use UTF-16, see
  # http://msdn.microsoft.com/en-us/library/dd374081.aspx
  # We need to read twice the data if it is UTF-16.  Assume the length
  # is already correct if a negative value is supplied.
  $len *= 2 if $utf16 > 0;

  my $str = read_and_unpack($fh, $where, "x[$offset]a[$len]");
  $str = decode('utf-16le', $str) if $utf16;
  return $str;
}

sub read_and_unpack_asciz {
  my($buf, $where, $offset) = @_;
  $offset //= 0;

  return read_and_unpack($buf, $where, "x[$offset]Z*");
}

sub read_and_unpack_utf16z {
  my($buf, $where, $offset) = @_;
  $offset //= 0;

  return read_and_unpack_str($buf, $where,
    $offset, index($buf, "\0\0", $offset) - $offset + 1,
    -1
  );
}


1;
