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

use Try::Tiny;

use File::Shortcut::Util qw(err);


=head1 NAME

File::Shortcut - Read and write Windows Shortcut Files aka Shell Links (*.lnk)


=head1 VERSION

Version 0.02


=cut

our $VERSION = '0.02';


=head1 SYNOPSIS

The function C<shortcut> and C<readshortcut> can be imported by your
script.  They are designed to behave like C<link> and C<readlink>
respectively:

    use File::Shortcut qw(shortcut readshortcut);
    use File::Spec::Win32;

    say shortcut("C:\\WINDOWS\\notepad.exe", "notepad.exe.lnk", {
      description => "The worst editor on earth",
    }) // die $File::Shortcut::Error;

    my $path = readshortcut("notepad.exe.lnk") // die $File::Shortcut::Error;
    my($vol, $dir, $file) = File::Spec::Win32->splitpath($path);


=head1 FUNCTIONS

=cut

# See L<"GLOBAL VARIABLES">
our $Error = "";
our $Debug = 0;


=head2 readshortcut EXPR

=head2 readshortcut

Returns the destination of a shortcut.  If there is some system error,
returns the undefined value and sets C<$File::Shortcut::Error> (and
probably also C<$!> (errno)).  EXPR can be either a string representing
a file path or a file handle.  B<In the latter case, binmode is set on
that file handle.>  If EXPR is omitted, uses C<$_>.

The return value is whatever path was stored in the Shortcut file, most
probably a Windows style path with backslashes.  You should use
L<File::Spec::Win32> to convert it to whatever format is used by your
OS.  B<An UNC path is a valid return value, too.>

=cut

sub readshortcut {
  my $file = @_ ? $_[0] : $_;

  if (ref $file) {
    croak "EXPR must be a file handle (or path)" if tell $file == -1;
  }
  else {
    open my $fh, '<', $file or err("open(%s): %s", $file, $!);
    $file = $fh;
  }
  binmode($file) or err("binmode(): %s", $!);

  require File::Shortcut::Reader;
  $Error = "";
  return try {
    return File::Shortcut::Reader::read_shortcut($file)->{path};
  }
  catch {
    die $_ unless $_ ~~ \$Error;
    return undef;
  }
}


=head2 shortcut OLDFILE, NEWFILE, METADATA

=head2 shortcut OLDFILE, NEWFILE

Creates a new filename linked to the old filename.  Returns true for
success, false otherwise.

Optionally, a METADATA hash can be used to set further values of the 
shortcut file.

=for comment
TODO: Document the format of the METADATA hash.

=cut

sub shortcut {
  my($source, $target, $options) = @_;
  $options ||= {};
  require File::Shortcut::Writer;
  $Error = "";
  return try {
    return File::Shortcut::Writer::write_shortcut($source, $target, $options);
  }
  catch {
    die $_ unless $_ ~~ \$Error;
    return undef;
  }
}


=head1 GLOBAL VARIABLES

=head2 $File::Shortcut::Error

If an error occurred, C<shortcut> and C<readshortcut> return undef and the
error string can be found in this variable.  The value is reset on each call.

Defaults to "".


=head2 $File::Shortcut::Debug

When this variable is set to a true value, C<readshortcut> generates a debug
trace of how it parses the shortcut file.  If the value is a file handle,
the trace will be printed to that handle, otherwise to C<STDERR>.

Defaults to 0.


=head1 AUTHOR

Malte S. Stretz C<< <mss at apache.org> >>


=head1 MOTIVATION

I needed a way to create Windows Shortcut Files on a Linux PDC without
resorting to Logon Scripts (since (a) these are a PITA, (b) not all
clients were Domain Members and (c) I also had to create links on a
read-only group share based on some LDAP information).

What I needed were shell commands akin to C<ln -s> and C<readlink>.


=head1 ACKNOWLEDGEMENTS

This module is heavily based on the information found at the following links:

=over

=item * [MS-SHLLINK] Microsoft: "Shell Link (.LNK) Binary File Format"

L<http://msdn.microsoft.com/en-us/library/dd871305.aspx>

=item * [CYANLAB2010] CYANLAB: "LNK Parsing: You’re doing it wrong"

L<http://blog.0x01000000.org/2010/08/13/lnk-parsing-youre-doing-it-wrong-ii/>

=item * [HAGER1998] Jesse Hager: "The Windows Shortcut File Format"

L<http://8bits.googlecode.com/files/The_Windows_Shortcut_File_Format.pdf>

=item * [STDLIB2007] Daniel at Stdlib.com: "Shortcut File Format (.lnk)"

L<http://www.stdlib.com/art6-Shortcut-File-Format-lnk.html>

=back


=head1 TO DO

These things are planned, in roughly descending order of importance:

=over

=item * Simple write support.

=item * Tests.

=item * OO interface to retrieve the metadata.

=item * Read support the full spectrum of Shortuct files.

=item * Full write support (if feasible).

=back


=head1 BUGS

Please report any bugs or feature requests to C<bug-file-shortcut at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-Shortcut>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

Patches, forks and pull requests are welcome, too.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::Shortcut


You can also look for information at:

=over

=item * GitHub: Code repository

L<https://github.com/mss/file-shortcut>

=item * RT: CPAN's request tracker

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=File-Shortcut>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-Shortcut>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-Shortcut>

=item * Search CPAN

L<http://search.cpan.org/dist/File-Shortcut/>

=back


=head1 COPYRIGHT

Copyright 2011 Malte S. Stretz L<http://msquadrat.de>.

Copyright 2011 Bernt Lorentz GmbH & Co. KG L<http://www.lorentz.de>.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=head1 SEE ALSO

L<Win32::Shortcut>
L<File::Spec::Win32>


=cut
1; # End of File::Shortcut
