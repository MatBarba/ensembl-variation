package Bio::EnsEMBL::Variation::OverlapConsequence;

use strict;
use warnings;

use Bio::EnsEMBL::Variation::Utils::VariationEffect;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub new_fast {
    my ($class, $hashref) = @_;
    return bless $hashref, $class;
}

sub dbID {
    my ($self, $dbID) = @_;
    $self->{dbID} = $dbID if $dbID;
    return $self->{dbID};
}

sub SO_term {
    my ($self, $SO_term) = @_;
    $self->{SO_term} = $SO_term if $SO_term;
    return $self->{SO_term};
}

sub feature_SO_term {
    my ($self, $feature_SO_term) = @_;
    $self->{feature_SO_term} = $feature_SO_term if $feature_SO_term;
    return $self->{feature_SO_term};
}

sub predicate {
    my ($self, $predicate) = @_;
    
    $self->{predicate} = $predicate if $predicate;
    
    if ($self->{predicate} && ref $self->{predicate} ne 'CODE') {
        my $name = $self->{predicate};
        if (defined &$name && $name =~ /^Bio::EnsEMBL::Variation::Utils::VariationEffect/) {
            $self->{predicate} = \&$name;
        }
    }
    
    return $self->{predicate};
}

sub rank {
    my ($self, $rank) = @_;
    $self->{rank} = $rank if $rank;
    return $self->{rank};
}

sub ensembl_term {
    my ($self, $ensembl_term) = @_;
    $self->{ensembl_term} = $ensembl_term if $ensembl_term;
    return $self->{ensembl_term};
}

sub SO_id {
    my ($self, $SO_id) = @_;
    $self->{SO_id} = $SO_id if $SO_id;
    return $self->{SO_id};
}

sub NCBI_term {
    my ($self, $NCBI_term) = @_;
    $self->{NCBI_term} = $NCBI_term if $NCBI_term;
    return $self->{NCBI_term};
}

sub is_definitive {
    my ($self, $is_definitive) = @_;
    $self->{is_definitive} = $is_definitive if defined $is_definitive;
    return $self->{is_definitive};
}

1;
