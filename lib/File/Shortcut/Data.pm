package File::Shortcut::Data;

use 5.10.0;

use warnings;
use strict;


# Defined in [MS-SHLLINK] 2.1.1
our @HEADER_FLAGS = qw(
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
);

# Defined in [MS-SHLLINK] 2.1.2
our @FILE_ATTRIBUTES = qw(
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
);

# Defined in [MS-SHLLINK] 2.3
our @LINK_INFO_FLAGS = qw(
  volume_id_and_local_base_path
  common_network_relative_link_and_path_suffix
);



1;