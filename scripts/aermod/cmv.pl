#!/usr/bin/perl

use strict;
use warnings;

use Date::Simple;
use Text::CSV ();
use Geo::Coordinates::UTM qw(latlon_to_utm latlon_to_utm_force_zone);

require 'aermod.subs';
require 'aermod_np.subs';

my $UW_GROUP = 'CMVU';
my $PORT_GROUP = 'CMVP';

my $grid_prefix = $ENV{'GRID_PREFIX'} || '12_';
my $run_group_suffix = $ENV{'RUN_GROUP_SUFFIX'} || '12';

# define state FIPS codes that will be skipped
my %drop_states = map { $_ => 1 } ('85', '98');

# check environment variables
foreach my $envvar (qw(REPORT_C1C2 REPORT_C3 SOURCE_GROUPS GROUP_PARAMS PORT_POLYGONS OUTPUT_DIR HOURLY_POLL)) {
  die "Environment variable '$envvar' must be set" unless $ENV{$envvar};
}

my $year = $ENV{'YEAR'};
my $hourly_poll = $ENV{'HOURLY_POLL'};

# load source group parameters
print "Reading source groups data...\n";
my $group_fh = open_input($ENV{'GROUP_PARAMS'});

my $csv_parser = Text::CSV->new();
my $header = $csv_parser->getline($group_fh);
$csv_parser->column_names(@$header);

my %group_params;
while (my $row = $csv_parser->getline_hr($group_fh)) {
  $group_params{$row->{'run_group'}} = {
    'release_height' => $row->{'release_height'},
    'sigma_z' => $row->{'sigma_z'}
  };
}
close $group_fh;

# load source group/SCC mapping
$group_fh = open_input($ENV{'SOURCE_GROUPS'});

$csv_parser = Text::CSV->new();
$header = $csv_parser->getline($group_fh);
$csv_parser->column_names(@$header);

my %scc_groups;
while (my $row = $csv_parser->getline_hr($group_fh)) {
  # pad SCCs to 20 characters to match SMOKE 4.0 output
  my $scc = sprintf "%020s", $row->{'scc'};

  if (exists $scc_groups{$scc}) {
    die "Duplicate SCC $row->{'scc'} in source groups file";
  }
  
  my $run_group = $row->{'run_group'};
  unless (exists $group_params{$run_group}) {
    die "Unknown run group name $run_group in source group/SCC mapping file";
  }

  $scc_groups{$scc}{'run_group'} = $run_group;
  $scc_groups{$scc}{'source_group'} = $row->{'source_group'};
}
close $group_fh;

# load port polygons
print "Reading polygon shape data...\n";
my $polygon_fh = open_input($ENV{'PORT_POLYGONS'});

$csv_parser = Text::CSV->new();
while ($header = $csv_parser->getline($polygon_fh)) {
  next if $header->[0] =~ /^#/;
  $csv_parser->column_names(@$header);
  last;
}

my %port_polygons;
my %port_areas;
while (my $row = $csv_parser->getline_hr($polygon_fh)) {
  my $facid = $row->{'facid'};
  unless (exists $port_polygons{$facid}) {
    $port_polygons{$facid} = [[$row->{'lon'}, $row->{'lat'}]];
    $port_areas{$facid} = $row->{'area'};
  } else {
    push @{ $port_polygons{$facid} }, [$row->{'lon'}, $row->{'lat'}];
  }
}
close $polygon_fh;

# check output directories
print "Checking output directories...\n";
my $output_dir = $ENV{'OUTPUT_DIR'};
die "Missing output directory $output_dir" unless -d $output_dir;

foreach my $dir (qw(locations parameters temporal emis)) {
  die "Missing output directory $output_dir/$dir" unless -d $output_dir . '/' . $dir;
}

my %handles;  # file handles

print "Processing AERMOD sources...\n";

foreach my $report (qw(REPORT_C1C2 REPORT_C3)) {
  my $src_prefix = 'c1_';
  my $grp_suffix = '_C1C2';
  my $port_suffix = 'c1c2';
  if ($report eq 'REPORT_C3') {
    $src_prefix = 'c3_';
    $grp_suffix = '_C3';
    $port_suffix = 'c3';
  }

  # open report file
  my $in_fh = open_input($ENV{$report});
  print "Reading $report file...\n";

  my %headers;
  my @pollutants;
  my %sources;  # list of SMOKE sources corresponding to each AERMOD source (grid cell or port shape)
  my %emissions;  # emissions by AERMOD source, region, and pollutant
  my %port_cell_emissions;  # summed emissions by port shape and grid cell

  while (my $line = <$in_fh>) {
    chomp $line;
    next if skip_line($line);

    my ($is_header, @data) = parse_report_line($line);

    if ($is_header) {
      parse_header(\@data, \%headers, \@pollutants, 'SE Longitude');
      
      # make sure pollutant for hourly factors is in the report
      my $found_poll = 0;
      foreach my $poll (@pollutants) {
        if ($poll eq $hourly_poll) {
          $found_poll = 1;
          last;
        }
      }
      die "Pollutant $hourly_poll not found in $report" unless $found_poll;
      
      next;
    }
    
    # skip excluded states
    my $region = substr($data[$headers{'Region'}], -5);
    my $state = substr($region, 0, 2);
    next if exists $drop_states{$state};
    
    # look up run group based on SCC
    my $scc = $data[$headers{'SCC'}];
    unless (exists $scc_groups{$scc}) {
      die "No run group defined for SCC $scc";
    }
    my $run_group = $scc_groups{$scc}{'run_group'};
    my $source_group = $scc_groups{$scc}{'source_group'};
    
    unless ($run_group eq $UW_GROUP || $run_group eq $PORT_GROUP) {
      die "Run group should be either $UW_GROUP or $PORT_GROUP for SCC $scc";
    }
    
    # build facility identifier: for underway, use grid cell, for port, use shape ID + FIPS
    my $cell = "G" . sprintf("%03d", $data[$headers{'X cell'}]) .
               "R" . sprintf("%03d", $data[$headers{'Y cell'}]);
    
    my $facility_id;
    my $source_id;
    my $vertices;
    
    if ($run_group eq $UW_GROUP) {
      $facility_id = $cell;
      $source_id = "${src_prefix}${grid_prefix}1";
    } else {
      my $shape_id = $data[$headers{'Char 2'}];
      $facility_id = "P" . sprintf("%05d", $shape_id) .
                     "F" . sprintf("%05d", $region);
      $source_id = "P" . sprintf("%05d", $shape_id) . $port_suffix;
      
      # look up vertices for port shape
      unless (exists $port_polygons{$facility_id}) {
        die "No port shape found for facility $facility_id";
      }
      $vertices = $port_polygons{$facility_id};
    }
    
    my $smoke_id = $data[$headers{'Source ID'}];

    unless (exists $sources{$facility_id}) {
      # store info about current AERMOD source
      $sources{$facility_id}{'smoke_ids'} = [$smoke_id];
      $sources{$facility_id}{'source_id'} = $source_id;
      
      $sources{$facility_id}{'run_group'} = $run_group;
      $sources{$facility_id}{'source_group'} = $source_group;
      
      $sources{$facility_id}{'region'} = $region;
      
      if ($run_group eq $PORT_GROUP) {
        $sources{$facility_id}{'first_vertex'} = @$vertices[0];
      }

      my @output;
      if ($run_group eq $UW_GROUP) {
        # prepare underway location output
        my $sw_lat = $data[$headers{'SW Latitude'}];
        my $sw_lon = $data[$headers{'SW Longitude'}];
        my ($zone, $utm_x, $utm_y) = latlon_to_utm(23, $sw_lat, $sw_lon);
        my $outzone = $zone;
        $outzone =~ s/\D//g; # strip latitude band designation from UTM zone
        
        @output = ();
        push @output, $run_group . $run_group_suffix;
        push @output, sprintf("%02d", $state);
        push @output, $facility_id;
        push @output, $source_id;
        push @output, $utm_x;
        push @output, $utm_y;
        push @output, $outzone;
        push @output, $sw_lon;
        push @output, $sw_lat;
        
        my $file = "$output_dir/locations/${run_group}_locations.csv";
        unless (exists $handles{$file}) {
          my $fh = open_output($file);
          print $fh "run_group,state,met_cell,src_id,utmx,utmy,utm_zone,lon,lat\n";
          $handles{$file} = $fh;
        }
        my $loc_fh = $handles{$file};
        print $loc_fh join(',', @output) . "\n";
            
        # prepare underway parameters output
        @output = ();
        push @output, $run_group . $run_group_suffix;
        push @output, $facility_id;
        push @output, $source_id;
        push @output, $group_params{$run_group . $grp_suffix}{'release_height'};
        push @output, "4"; # number of vertices
        push @output, $group_params{$run_group . $grp_suffix}{'sigma_z'};
        push @output, $utm_x;
        push @output, $utm_y;

        my $nw_lat = $data[$headers{'NW Latitude'}];
        my $nw_lon = $data[$headers{'NW Longitude'}];
        ($zone, $utm_x, $utm_y) = latlon_to_utm_force_zone(23, $zone, $nw_lat, $nw_lon);
        push @output, $utm_x;
        push @output, $utm_y;

        my $ne_lat = $data[$headers{'NE Latitude'}];
        my $ne_lon = $data[$headers{'NE Longitude'}];
        ($zone, $utm_x, $utm_y) = latlon_to_utm_force_zone(23, $zone, $ne_lat, $ne_lon);
        push @output, $utm_x;
        push @output, $utm_y;

        my $se_lat = $data[$headers{'SE Latitude'}];
        my $se_lon = $data[$headers{'SE Longitude'}];
        ($zone, $utm_x, $utm_y) = latlon_to_utm_force_zone(23, $zone, $se_lat, $se_lon);
        push @output, $utm_x;
        push @output, $utm_y;

        push @output, $sw_lon;
        push @output, $sw_lat;
        push @output, $nw_lon;
        push @output, $nw_lat;
        push @output, $ne_lon;
        push @output, $ne_lat;
        push @output, $se_lon;
        push @output, $se_lat;
        
        $file = "$output_dir/parameters/${run_group}_area_parameters.csv";
        unless (exists $handles{$file}) {
          my $fh = open_output($file);
          write_parameter_header($fh);
          $handles{$file} = $fh;
        }
        my $param_fh = $handles{$file};
        print $param_fh join(',', @output) . "\n";
      
      } else {
        # prepare port parameters output
        my @common;
        push @common, sprintf("%02d", $state);
        push @common, $facility_id;
        push @common, $source_id;
        push @common, "AREAPOLY";
        push @common, $port_areas{$facility_id};
        push @common, $group_params{$run_group . $grp_suffix}{'release_height'};
        push @common, scalar(@$vertices);
        push @common, $group_params{$run_group . $grp_suffix}{'sigma_z'};
        
        my $first = 1;
        my ($zone, $utm_x, $utm_y);
        foreach my $coords (@$vertices) {
          my $lon = @$coords[0];
          my $lat = @$coords[1];
          @output = @common;
          
          if ($first) {
            ($zone, $utm_x, $utm_y) = latlon_to_utm(23, $lat, $lon);
            $first = 0;
          } else {
            ($zone, $utm_x, $utm_y) = latlon_to_utm_force_zone(23, $zone, $lat, $lon);
          }
          
          push @output, $utm_x;
          push @output, $utm_y;
          push @output, $lon;
          push @output, $lat;
          
          my $file = "$output_dir/parameters/${run_group}_area_parameters.csv";
          unless (exists $handles{$file}) {
            my $fh = open_output($file);
            print $fh "state,facid,src_id,src_type,area,rel_ht,verts,sz,utmx,utmy,lon,lat\n";
            $handles{$file} = $fh;
          }
          my $param_fh = $handles{$file};
          print $param_fh join(',', @output) . "\n";
        }
      }
    } else {
      push @{ $sources{$facility_id}{'smoke_ids'} }, $smoke_id;
    }

    # store emissions
    foreach my $poll (@pollutants) {
      my $emis_val = $data[$headers{$poll}];
      if ($run_group eq $UW_GROUP) {
        $emissions{$facility_id}{$region}{$poll} =
          ($emissions{$facility_id}{$region}{$poll} || 0) + $emis_val;
      } else {
        $emissions{$facility_id}{$poll} =
          ($emissions{$facility_id}{$poll} || 0) + $emis_val;
      
        # store total emissions for port/grid cell combos
        $port_cell_emissions{$facility_id}{$cell}{'emis'} =
          ($port_cell_emissions{$facility_id}{$cell}{'emis'} || 0) + $emis_val;
        $port_cell_emissions{$facility_id}{$cell}{'col'} = $data[$headers{'X cell'}];
        $port_cell_emissions{$facility_id}{$cell}{'row'} = $data[$headers{'Y cell'}];
      }
    }
  }
  close $in_fh;
  
  # prepare port location output
  foreach my $facility_id (sort keys %port_cell_emissions) {
    # determine grid cell with the maximum emissions total
    my $max_cell;
    my $max_emis = -1;
    foreach my $cell (sort keys $port_cell_emissions{$facility_id}) {
      my $cell_emis = $port_cell_emissions{$facility_id}{$cell}{'emis'};
      if ($cell_emis > $max_emis) {
        $max_emis = $cell_emis;
        $max_cell = $cell;
      }
    }
    $sources{$facility_id}{'max_cell'} = $max_cell;
    
    my $run_group = $sources{$facility_id}{'run_group'};
    my $region = $sources{$facility_id}{'region'};
    my $state = substr($region, 0, 2);
    my $vertex_lon = $sources{$facility_id}{'first_vertex'}[0];
    my $vertex_lat = $sources{$facility_id}{'first_vertex'}[1];
    my ($zone, $utm_x, $utm_y) = latlon_to_utm(23, $vertex_lat, $vertex_lon);
    my $outzone = $zone;
    $outzone =~ s/\D//g; # strip latitude band designation from UTM zone
    
    my @output;
    push @output, sprintf("%02d", $state);
    push @output, sprintf("%05d", $region);
    push @output, $facility_id;
    push @output, $sources{$facility_id}{'source_id'};
    push @output, 'AREAPOLY';
    push @output, $port_cell_emissions{$facility_id}{$max_cell}{'col'};
    push @output, $port_cell_emissions{$facility_id}{$max_cell}{'row'};
    push @output, $utm_x;
    push @output, $utm_y;
    push @output, $outzone;
    push @output, $vertex_lon;
    push @output, $vertex_lat;
    
    my $file = "$output_dir/locations/${run_group}_locations.csv";
    unless (exists $handles{$file}) {
      my $fh = open_output($file);
      print $fh "state,region,facid,src_id,src_type,col,row,utmx,utmy,utm_zone,lon,lat\n";
      $handles{$file} = $fh;
    }
    my $loc_fh = $handles{$file};
    print $loc_fh join(',', @output) . "\n";
  }

  # prepare source list output
  my $file = "$output_dir/temporal/CMV_${src_prefix}source_list.csv";
  my $src_fh = open_output($file);
  print $src_fh "state,file_prefix,run_group,facid,src_id,poll,annual_emis,smoke_ids\n";
  
  foreach my $facility_id (sort keys %emissions) {
    my $run_group = $sources{$facility_id}{'run_group'};
    my $source_id = $sources{$facility_id}{'source_id'};
    
    my @output;
    push @output, sprintf("%02d", substr($sources{$facility_id}{'region'}, 0, 2));
    push @output, $run_group;
    push @output, $run_group . $run_group_suffix;
    
    if ($run_group eq $UW_GROUP) {
      push @output, $facility_id;
    } else {
      push @output, $sources{$facility_id}{'max_cell'};
    }
    
    push @output, $source_id;
    push @output, $hourly_poll;
    
    my $emis_val = 0;
    if ($run_group eq $UW_GROUP) {
      foreach my $region (sort keys $emissions{$facility_id}) {
        $emis_val = $emis_val + $emissions{$facility_id}{$region}{$hourly_poll};
      }
    } else {
      $emis_val = $emissions{$facility_id}{$hourly_poll};
    }
    push @output, $emis_val;
    
    my @source_list = @{ $sources{$facility_id}{'smoke_ids'} };
    push @output, @source_list;
    # pad source list with zeroes if needed
    warn "More than 20 SMOKE sources for $facility_id" if scalar(@source_list) > 20;
    push @output, 0 for (1..(20 - scalar(@source_list)));
    
    print $src_fh join (',', @output) . "\n";
  }
  close $src_fh;

  # prepare emissions output
  foreach my $facility_id (sort keys %emissions) {
    my $source_id = $sources{$facility_id}{'source_id'};
    my $run_group = $sources{$facility_id}{'run_group'};
    my $source_group = $sources{$facility_id}{'source_group'};
    
    my $file = "$output_dir/emis/${run_group}_emis.csv";
    unless (exists $handles{$file}) {
      my $fh = open_output($file);
      if ($run_group eq $UW_GROUP) {
        print $fh "run_group,region,met_cell,src_id,source_group,smoke_name,ann_value\n";
      } else {
        print $fh "state,run_group,facid,src_id,source_group,smoke_name,ann_value\n";
      }
      $handles{$file} = $fh;
    }
    my $emis_fh = $handles{$file};
    
    if ($run_group eq $UW_GROUP) {
      foreach my $region (sort keys $emissions{$facility_id}) {
        foreach my $poll (sort keys $emissions{$facility_id}{$region}) {
          my $emis_val = $emissions{$facility_id}{$region}{$poll};
          next if $emis_val == 0.0;
          
          my @output;
          push @output, $run_group . $run_group_suffix;
          push @output, sprintf("%05d", $region);
          push @output, $facility_id;
          push @output, $source_id;
          push @output, $source_group;
          push @output, $poll;
          push @output, $emis_val;
          print $emis_fh join(',', @output) . "\n";
        }
      }
    } else {
      foreach my $poll (sort keys $emissions{$facility_id}) {
        my $emis_val = $emissions{$facility_id}{$poll};
        next if $emis_val == 0.0;
        
        my @output;
        push @output, substr($sources{$facility_id}{'region'}, 0, 2);
        push @output, $run_group . $run_group_suffix;
        push @output, $facility_id;
        push @output, $source_id;
        push @output, $source_group;
        push @output, $poll;
        push @output, $emis_val;
        print $emis_fh join(',', @output) . "\n";
      }
    }
  }
}

foreach my $fh (values %handles) {
  close $fh;
}

print "Done.\n";
