package File::Shortcut;

use 5.10.0;

use warnings;
use strict;

=head1 NAME

File::Shortcut - The great new File::Shortcut!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use File::Shortcut;

    my $foo = File::Shortcut->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=cut

my $errstr = "";

sub _err {
  my($errstr) = shift;
  $$errstr = sprintf(@_);
  return undef;
}

=head2 read_shortcut

=cut


sub read_shortcut {
  return _read_shortcut(\$errstr, @_);
}

sub _read_shortcut {
  my($errstr, $file) = @_;

  binmode($file) or return _err("binmode(): %s", $!);

  my $buf, $len;

  $len = 4 + 16 + 4 + 4 + 8 * 3 + 4 * 4 + 4 * 2;
  read($file, $buf, $len) == $len or return _err("read(): header: expected %d bytes", $len);

  # http://8bits.googlecode.com/files/The_Windows_Shortcut_File_Format.pdf
  # http://www.stdlib.com/art6-Shortcut-File-Format-lnk.html
  my %header;
  @header{qw(
    magic
    guid
    flags
    attribs
    ctime
    atime
    mtime
    flen
    icon
    window
    hotkey
    reserved
    reserved
  )} = unpack(join('',
    "V",   #  4 bytes Always 4C 00 00 00
    "a16", # 16 bytes GUID for shortcut files
    "V",   #  1 dword Shortcut flags
    "V",   #  1 dword Target file flags
    "a8",  #  1 qword Creation time
    "a8",  #  1 qword Last access time
    "a8",  #  1 qword Modification time
    "V",   #  1 dword File length
    "V",   #  1 dword Icon number
    "V",   #  1 dword Show Window
    "V",   #  1 dword Hot Key
    "V",   #  1 dword Reserved
    "V",   #  1 dword Reserved
  ), $buf);

  unless ($header{magic} == ord("L")) {
    return _err("Wrong magic %08x", $header{magic});
  }
  unless ($header{guid} == "\x01\x14\x02\x00\x00\x00\x00\xc0\x00\x00\x00\x00\x46") {
    return _err("Wrong GUID %32x", $header{guid});
  }

  delete $header{reserved};

  $header{flags} = {
    _raw        => $header{flags},
    idlist      => $header{flags} & (1 <<  0),
    fod         => $header{flags} & (1 <<  1),
    description => $header{flags} & (1 <<  2),
    relative    => $header{flags} & (1 <<  3),
    workdir     => $header{flags} & (1 <<  4),
    args        => $header{flags} & (1 <<  5),
    icon        => $header{flags} & (1 <<  6),
  };
  $header{attribs} = {
    _raw       => $header{attribs},
    readonly   => $header{attribs} & (1 <<  0),
    hidden     => $header{attribs} & (1 <<  1),
    system     => $header{attribs} & (1 <<  2),
    volume     => $header{attribs} & (1 <<  3),
    dir        => $header{attribs} & (1 <<  4),
    archive    => $header{attribs} & (1 <<  5),
    encrypted  => $header{attribs} & (1 <<  6),
    normal     => $header{attribs} & (1 <<  7),
    temp       => $header{attribs} & (1 <<  8),
    sparse     => $header{attribs} & (1 <<  9),
    reparse    => $header{attribs} & (1 << 10),
    compressed => $header{attribs} & (1 << 11),
    offline    => $header{attribs} & (1 << 12),
  };
  
  $header{window} = do { given ($header{window}) {
    when ( 0) { return "hide" };
    when ( 1) { return "normal" };
    when ( 2) { return "minimized" };
    when ( 3) { return "maximized" };
    when ( 4) { return "noactivate" };
    when ( 5) { return "show" };
    when ( 6) { return "minimize" };
    when ( 7) { return "minimizenoactive" };
    when ( 8) { return "na" };
    when ( 9) { return "restore" };
    when (10) { return "default" };
    default   { return undef };
  }; };

  my %struct = (
    header => \%header,
    my %data;
    @data(qw(
      len
      offset
      remote
      volinfo
      basepath
      netvol
      path
    )) = unpack("VVVVVVV", $bug);
    if ($data{remote} > 1) {
      # error
    }
    
  );
  
  if ($header{flags}->{idlist}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): idlist: expected %d bytes", $len);
    $len = unpack("v", $buf);
    
    while (true) {
      $len = 2;
      read($file, $buf, $len) == $len or _err("read(): idlist: expected %d bytes", $len);
      $len = unpack("v", $buf);
      break if ($len == 0);
      $len -= 2;
      
      # TODO
    }
  }

  if ($header{flags}->{description}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): description: expected %d bytes", $len);
    $len = unpack("v", $buf);
    read($file, $buf, $len) == $len or _err("read(): description: expected %d bytes", $len);
    $struct{description} = unpack("A$len", $buf);
  }
  
  if ($header{flags}->{relative}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): relative: expected %d bytes", $len);
    $len = unpack("v", $buf);
    read($file, $buf, $len) == $len or _err("read(): relative: expected %d bytes", $len);
    $struct{relative} = unpack("A$len", $buf);
  }
  
  if ($header{flags}->{workdir}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): workdir: expected %d bytes", $len);
    $len = unpack("v", $buf);
    read($file, $buf, $len) == $len or _err("read(): workdir: expected %d bytes", $len);
    $struct{workdir} = unpack("A$len", $buf);
  }
  
  if ($header{flags}->{args}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): args: expected %d bytes", $len);
    $len = unpack("v", $buf);
    read($file, $buf, $len) == $len or _err("read(): args: expected %d bytes", $len);
    $struct{args} = unpack("A$len", $buf);
  }
  
  if ($header{flags}->{icon}) {
    $len = 2;
    read($file, $buf, $len) == $len or _err("read(): icon: expected %d bytes", $len);
    $len = unpack("v", $buf);
    read($file, $buf, $len) == $len or _err("read(): icon: expected %d bytes", $len);
    $struct{icon} = unpack("A$len", $buf);
  }

  return $struct;
}


=head2 write_shortcut

=cut

sub write_shortcut {
  
}


=head1 AUTHOR

Malte S. Stretz, C<< <mss at apache.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-file-shortcut at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-Shortcut>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




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


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Malte S. Stretz.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of File::Shortcut
