#
# Ensembl module for Bio::EnsEMBL::Variation::DBSQL::BaseGenotypeAdaptor
#
# Copyright (c) 2005 Ensembl
#
# You may distribute this module under the same terms as perl itself
#
#

=head1 NAME

Bio::EnsEMBL::Variation::DBSQL::BaseGenotypeAdaptor

=head1 SYNOPSIS

Abstract class - should not be instantiated.  Implementation of
abstract methods must be performed by subclasses.

Base adaptors provides:

#using the adaptor of the subclass, retrieve all Genotypes from MultipleGenotype table
$genotypes = $ig_adaptor->fetch_all_by_Variation($variation_id);

#using the adaptor of the subclass and given a slice, returns all genotypes in the region
$genotypes = $ig_adaptor->fetch_sll_by_Slice($slice);


=head1 DESCRIPTION

This adaptor provides database connectivity for IndividualGenotype objects.
IndividualGenotypes may be retrieved from the Ensembl variation database by
several means using this module.

=head1 AUTHOR - Daniel Rios

=head1 CONTACT

Post questions to the Ensembl development list ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut
package Bio::EnsEMBL::Variation::DBSQL::BaseGenotypeAdaptor;

use strict;
use warnings;

use vars qw(@ISA);

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Variation::IndividualGenotype;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);


@ISA = ('Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor');


=head2 fetch_all_by_Variation

  Arg [1]    : Bio::EnsEMBL::Variation $variation
  Example    : my $var = $variation_adaptor->fetch_by_name( "rs1121" )
               $igtypes = $igtype_adaptor->fetch_all_by_Variation( $var )
  Description: Retrieves a list of individual genotypes for the given Variation.
               If none are available an empty listref is returned.
  Returntype : listref Bio::EnsEMBL::Variation::IndividualGenotype 
  Exceptions : none
  Caller     : general

=cut


sub fetch_all_by_Variation {
    my $self = shift;
    my $variation = shift;

    if(!ref($variation) || !$variation->isa('Bio::EnsEMBL::Variation::Variation')) {
	throw('Bio::EnsEMBL::Variation::Variation argument expected');
    }

    if(!defined($variation->dbID())) {
	warning("Cannot retrieve genotypes for variation without set dbID");
	return [];
    }	  
    my $res;
    if (!$self->_multiple){
	push @{$res},@{$self->generic_fetch("ig.variation_id = " . $variation->dbID())}; #to select data from individual_genotype_single_bp
	$self->_multiple(1);
    }
    push @{$res}, @{$self->generic_fetch("ig.variation_id = " . $variation->dbID())}; #to select data from individual_genotype_multiple_bp
    return $res;
}

sub _tables{
    my $self = shift;

    return (['individual_genotype_single_bp','ig'],['variation_feature','vf']) if (!$self->_multiple);
    return (['individual_genotype_multiple_bp','ig'],['variation_feature','vf']) if ($self->_multiple);
    
}

sub _columns{
    return qw(ig.sample_id ig.variation_id ig.allele_1 ig.allele_2 vf.seq_region_id vf.seq_region_start vf.seq_region_end vf.seq_region_strand);
}

sub _default_where_clause  {

  my $self = shift;

  return 'vf.variation_id = ig.variation_id';

}

sub _objs_from_sth{
    my ($self, $sth, $mapper, $dest_slice) = @_;
    
    #
    # This code is ugly because an attempt has been made to remove as many
    # function calls as possible for speed purposes.  Thus many caches and
    # a fair bit of gymnastics is used.
    #
    
    my $sa = $self->db()->dnadb()->get_SliceAdaptor();
    
    my @results;
    my %slice_hash;
    my %sr_name_hash;
    my %sr_cs_hash;
    my %individual_hash;
    my %variation_hash;

  my ($sample_id, $variation_id, $seq_region_id, $seq_region_start,
      $seq_region_end, $seq_region_strand, $allele_1, $allele_2);

  $sth->bind_columns(\$sample_id, \$variation_id, \$allele_1, \$allele_2,
		     \$seq_region_id, \$seq_region_start, \$seq_region_end, \$seq_region_strand);

  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
    $asm_cs = $mapper->assembled_CoordSystem();
    $cmp_cs = $mapper->component_CoordSystem();
    $asm_cs_name = $asm_cs->name();
    $asm_cs_vers = $asm_cs->version();
    $cmp_cs_name = $cmp_cs->name();
    $cmp_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
  }

  FEATURE: while($sth->fetch()) {
    #get the slice object
    my $slice = $slice_hash{"ID:".$seq_region_id};
    if(!$slice) {
      $slice = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{"ID:".$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id} = $slice->coord_system();
    }
    #
    # remap the feature coordinates to another coord system
    # if a mapper was provided
    #
    if($mapper) {
      my $sr_name = $sr_name_hash{$seq_region_id};
      my $sr_cs   = $sr_cs_hash{$seq_region_id};

      ($sr_name,$seq_region_start,$seq_region_end,$seq_region_strand) =
        $mapper->fastmap($sr_name, $seq_region_start, $seq_region_end,
                          $seq_region_strand, $sr_cs);

      #skip features that map to gaps or coord system boundaries
      next FEATURE if(!defined($sr_name));

      #get a slice in the coord system we just mapped to
      if($asm_cs == $sr_cs || ($cmp_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
        $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"} ||=
          $sa->fetch_by_region($cmp_cs_name, $sr_name,undef, undef, undef,
                               $cmp_cs_vers);
      } else {
        $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"} ||=
          $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef,
                               $asm_cs_vers);
      }
  }

    #
    # If a destination slice was provided convert the coords
    # If the dest_slice starts at 1 and is foward strand, nothing needs doing
    #
    if($dest_slice) {
	if($dest_slice_start != 1 || $dest_slice_strand != 1) {
	    if($dest_slice_strand == 1) {
		$seq_region_start = $seq_region_start - $dest_slice_start + 1;
		$seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
	    } else {
		my $tmp_seq_region_start = $seq_region_start;
		$seq_region_start = $dest_slice_end - $seq_region_end + 1;
		$seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
		$seq_region_strand *= -1;
	    }
	    
	    #throw away features off the end of the requested slice
	    if($seq_region_end < 1 || $seq_region_start > $dest_slice_length) {
		next FEATURE;
	    }
	}
	$slice = $dest_slice;
    }

    my $igtype = Bio::EnsEMBL::Variation::IndividualGenotype->new_fast({
	'start'    => $seq_region_start,
	'end'      => $seq_region_end,
	'strand'   => $seq_region_strand,
	'slice'    => $slice,	    
	'allele1'  => $allele_1,
	'allele2' => $allele_2,
    });
    $individual_hash{$sample_id} ||= [];
    $variation_hash{$sample_id} ||=[];
    push @{$individual_hash{$sample_id}}, $igtype;
    push @{$variation_hash{$variation_id}},$igtype;
    push @results, $igtype;
}
    # get all variations in one query (faster)
    # and add to already created genotypes
    my @var_ids = keys %variation_hash;
    my $va = $self->db()->get_VariationAdaptor();
    my $vars = $va->fetch_all_by_dbID_list(\@var_ids);
    
    foreach my $v (@$vars) {
	foreach my $igty (@{$variation_hash{$v->dbID()}}) {
	    $igty->variation($v);
	}
    }
    
    # get all individual in one query (faster)
    # and add to already created genotypes
    my @ind_ids = keys %individual_hash;
    
    my $ia = $self->db()->get_IndividualAdaptor();
    my $inds = $ia->fetch_all_by_dbID_list(\@ind_ids);
    
    foreach my $i (@$inds) {
	foreach my $igty (@{$individual_hash{$i->dbID()}}) {
	    $igty->individual($i);
	}
    }
    return \@results;
}


sub _multiple{
    my $self = shift;
    $self->{'_multiple'} = shift if (@_);
    return $self->{'_multiple'};

}

1;
