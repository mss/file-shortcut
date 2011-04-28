package File::Shortcut;

use 5.10.0;

use warnings;
use strict;

use parent qw(Exporter);
our @EXPORT_OK = qw(
  shortcut
  readshortcut
);


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
    } or die $File::Shortcut::Error;

    my $path = readshortcut("notepad.exe.lnk") or die $File::Shortcut::Error;
    my($vol, $dir, $file) = File::Spec::Win32->splitpath($path);


=head1 EXPORT

The following functions can be imported into your script:

    shortcut
    readshortcut


=head1 SUBROUTINES/METHODS

=cut

our $Error = "";

our $Debug = 0;

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
  require File::Shortcut::Reader;
  return File::Shortcut::Reader::readshortcut($file);
}

=head2 shortcut OLDFILE, NEWFILE, METADATA

=head2 shortcut OLDFILE, NEWFILE

Creates a new filename linked to the old filename.  Returns true for
success, false otherwise.

Optionally, a METADATA hash can be used to set further values of the 
shortcut file.  TODO: format

=cut

sub shortcut {
  my($source, $target, $options) = @_;
  $options ||= {};
  require File::Shortcut::Writer;
  die "Not implemented";
  #return File::Shortcut::Writer::writeshortcut($source, $target, $options);
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
