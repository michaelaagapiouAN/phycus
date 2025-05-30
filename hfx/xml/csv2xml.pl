#!/usr/bin/perl
use strict;
use warnings;
use Text::CSV;
use XML::Writer;
use XML::LibXML;
use IO::File;
use Getopt::Long;

# Default paths (optional)
my $csv_file;
my $config_file;
my $output_xml_file;
my $xsd_file = 'hfx_schema.xsd'; # Default XSD file (update the path as needed)

# Optional command-line arguments
GetOptions(
    'csv=s'    => \$csv_file,
    'config=s' => \$config_file,
    'output=s' => \$output_xml_file
) or die "Usage: $0 [--csv <haplotype_csv_file>] [--config <config_file>] [--output <output_xml_file>]\n";

# 1) Read optional config file for meta data, or use defaults
my %config = (
    locus       => 'HLA-DRB1',
    resolution  => '2-Field',
    method      => 'Unknown',
    parameter   => 'Unknown',
    value       => 'Unknown',
    geoCode     => 'Unknown',
    ethnicity   => 'Unknown',
    inputSize   => '0',
    kind        => 'Unknown',
    version     => 'Unknown'
);

# If config file is provided, override default metadata with its values
if ($config_file) {
    open my $cfg_fh, '<', $config_file or die "Cannot open config file: $!";
    while (<$cfg_fh>) {
        chomp;
        my ($key, $value) = split(/\s*=\s*/, $_);
        $config{$key} = $value;
    }
    close $cfg_fh;
}

# 2) Read and parse CSV file if provided, or use an empty dataset
my @haplotype_data;
if ($csv_file) {
    my $csv = Text::CSV->new({ binary => 1 });
    open my $csv_fh, '<', $csv_file or die "Cannot open CSV file: $!";
    while (my $row = $csv->getline($csv_fh)) {
        my ($haplotype, $frequency) = @$row;
        push @haplotype_data, { haplotype => $haplotype, frequency => $frequency };
    }
    close $csv_fh;
}

# 3) Prepare output destination (file or stdout)
my $output;
if ($output_xml_file) {
    $output = IO::File->new(">$output_xml_file");
} else {
    $output = *STDOUT;
}

# 4) Generate XML based on XSD and CSV data (or empty frequency section if no CSV)
my $writer = XML::Writer->new(OUTPUT => $output, DATA_MODE => 1, DATA_INDENT => 4);

$writer->xmlDecl('UTF-8');
$writer->startTag('hfxHaplotypeList');

# Add metadata from config (or defaults if config file not provided)
$writer->startTag('metaData');

# OutputResolution
$writer->startTag('outputResolution');
$writer->dataElement('locus', $config{'locus'});
if ($config{'resolution'}) {
    $writer->dataElement('resolution', $config{'resolution'});
}
$writer->endTag('outputResolution');

# hfeMethod
$writer->startTag('hfeMethod');
$writer->dataElement('method', $config{'method'});
$writer->startTag('parameters');
$writer->dataElement('parameter', $config{'parameter'});
$writer->dataElement('value', $config{'value'});
$writer->endTag('parameters');
$writer->endTag('hfeMethod');

# cohortDescription
$writer->startTag('cohortDescription');
$writer->startTag('population');
$writer->dataElement('geoCode', $config{'geoCode'});
$writer->dataElement('ethnicity', $config{'ethnicity'});
$writer->dataElement('species', $config{'species'});
$writer->dataElement('description', $config{'description'});
$writer->endTag('population');
$writer->dataElement('inputSize', $config{'inputSize'});
$writer->endTag('cohortDescription');

# nomenclatureUsed
$writer->startTag('nomenclatureUsed');
$writer->dataElement('kind', $config{'kind'});
$writer->dataElement('version', $config{'version'});
$writer->endTag('nomenclatureUsed');

$writer->endTag('metaData');

# Add haplotype frequency data if CSV was provided, otherwise skip
if (@haplotype_data) {
    foreach my $data (@haplotype_data) {
        $writer->startTag('frequencyData');
        $writer->dataElement('haplotype', $data->{haplotype});
        $writer->dataElement('frequency', $data->{frequency});
        $writer->endTag('frequencyData');
    }
}

$writer->endTag('hfxHaplotypeList');
$writer->end();

$output->close if $output_xml_file;

# 5) Validate the generated XML against the XSD
if ($output_xml_file) {
    my $schema = XML::LibXML::Schema->new(location => $xsd_file);

    # Load the generated XML file
    my $doc = XML::LibXML->load_xml(location => $output_xml_file);

    # Perform validation
    eval { $schema->validate($doc); };
    
    if ($@) {
        die "XML validation failed: $@\n";
    } else {
        print "XML successfully validated against the schema!\n";
    }
}
