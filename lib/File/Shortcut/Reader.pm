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
  map_bits
  parse_filetime
);


sub readshortcut {
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

  my %struct = (
    header => $header,
  );

  # [MS-SHLLINK] 2.1.1
  $header->{flags} = map_bits($header->{flags}, qw(
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

  # [MS-SHLLINK] 2.3
  if ($header->{flags}->{has_link_info}) {
    my $len = read_and_unpack($fh, "link_info/size", "L");
    $len -= sizeof("L");

    # [MS-SHLLINK] 2.1.1
    if ($header->{flags}->{force_no_link_info}) {
      read_and_unpack($fh, "link_info/skip", skip => "x[$len]");
    }
    else {
      # [MS-SHLLINK] 2.3
      my $hlen = read_and_unpack($fh, "link_info/head/size", "L");
      $len -= $hlen - sizeof("L");

      my $flags = read_and_unpack($fh, "link_info/head/flags", "L");
      $flags = map_bits($flags, qw(
        volume_id_and_local_base_path
        common_network_relative_link_and_path_suffix
      ));

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

      my $buf = read_and_unpack($fh, "link_info/data", "a[$len]");

      # [MS-SHLLINK] 2.3.1
      if (defined $data->{volume_id}) {
        my $offset = $data->{volume_id};
        my $size = read_and_unpack($buf, "link_info/data/volume_id/size",
          "x[$offset]L"
        );

        my $buf = read_and_unpack($buf, "link_info/data/volume_id",
          "x[$offset]x[L]a[$size]");
        my $volume = read_and_unpack($buf, "link_info/data/volume_id/head",
          drive_type          => "L",
          drive_serial_number => "L",
          volume_label_offset => "L",
        );

        $offset = delete $volume->{volume_label_offset};
        if ($offset != 0x14) {
          $offset -= sizeof("L");
          $volume->{volume_label} = read_and_unpack($buf, "link_info/data/volume_id",
            "x[$offset]Z*"
          );
        }
        else {
          $offset = read_and_unpack($buf, "link_info/data/volume_id/volume_label_unicode_offset",
            "x[L4]L"
          );
          $offset -= sizeof("L");
          my $len = index($buf, "\0\0", $offset) - $offset + 1;
          $volume->{volume_label} = decode('utf-16le', read_and_unpack($buf, "link_info/data/volume_id/volume_label_unicode",
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
        $data->{$key} = read_and_unpack($buf, "link_info/data/$key",
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
      my $len = read_and_unpack($fh, "$key/size", "S");
      next unless $len;

      # [MS-SHLLINK] 2.1.1; http://msdn.microsoft.com/en-us/library/dd374081.aspx
      $len *= 2 if $header->{flags}->{is_unicode};
      my $str = read_and_unpack($fh, "$key/data", "a[$len]");
      $str = decode('utf-16le', $str) if $header->{flags}->{is_unicode};

      $struct{$key} = $str;
    }
  }
  # TODO: delete $header->{flags};

  # [MS-SHLLINK] 2.1.2
  $header->{attrs} = map_bits($header->{attrs}, qw(
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
    $header->{$key} = parse_filetime($header->{$key});
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

1;
