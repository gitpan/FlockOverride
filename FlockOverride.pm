package File::ManualFlock::FlockOverride;
#===================================================================#

#======================================#
# Version Info                         #
#===================================================================#

$File::ManualFlock::FlockOverride::VERSION = '1.0.0';

#======================================#
# Dependencies                         #
#===================================================================#

#--------------------------------------#
# Standard Dependencies

use strict;

#--------------------------------------#
# %lh_keep_alive holds lock handles returned
# by File::ManualFlock::mflock() so that
# they stay in scope in the File::ManualFlock::FlockOverride::flock()
# caller's scope even after File::ManualFlock::FlockOverride::flock() 
# finishes executing.  Otherwise, the lock
# handles returned from File::ManualFlock::mflock()
# to File::ManualFlock::FlockOverride::flock()
# would go out of scope and the objects
# that they refer to would be destroyed,
# thereby also destroying the associated
# lock files.

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS %handles_to_names %lh_keep_alive);
#use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS %handles_to_names);

#--------------------------------------#
# Programmatic Dependencies

use File::Basename;
use File::ManualFlock;
use File::ManualFlock::Constants;
use Cwd qw( getcwd abs_path );

require Exporter;

#======================================#
# Inheritance                          #
#===================================================================#

@ISA = qw(Exporter);
@EXPORT_OK = qw(open close flock %lh_keep_alive );
%EXPORT_TAGS = ( 'flock_override'   => [qw(open close flock %lh_keep_alive)] );

#======================================#
# Public Methods                       #
#===================================================================#

# see perlsub under "Overriding Builtin Functions" regarding
# the use (when needed to implement flock used by a I<different> 
# package than the importing package) of the syntax
# use File::FlockDir qw(GLOBAL_open GLOBAL_close GLOBAL_flock)

sub import {
    my $pkg = shift;
    return unless @_;
    my $sym = shift;
    my $where = ($sym =~ s/^GLOBAL_// ? 'CORE::GLOBAL' : caller(0));
    $pkg->export($where, $sym, @_);
}

#-------------------------------------------------------------------#

# override perl flock
sub flock (*;$)
{    
  my $fh = shift;
  my $lock = shift; 
  
  my $filepath = $handles_to_names{$fh};
  my $mf = new File::ManualFlock;

  $lh_keep_alive{$fh} = $mf->mflock( $filepath, $lock, MFL_INFINITE, MFL_INFINITE );  
  #$mf->mflock( $filepath, $lock, MFL_INFINITE, MFL_INFINITE );  
  
  return $lh_keep_alive{$fh}->{'last_result'};

}

#-------------------------------------------------------------------#

# override open to save pathname for the handle

# must make sure name saved is full filepath
sub open (*;$) {
    my $fh = shift;
    my $spec = shift;
    my $retval;
    no strict 'refs';
    $retval = CORE::open(*$fh, $spec); 
    # hack for > 5.005 compatibility...
    eval('*' . (caller(0))[0] . '::' . $fh . '= $fh;');
    use strict 'refs';
    if($retval) {
        $spec =~ /\A[\s+<>]*(.+)\s*/; 
        if($1) {
            my $t = $1;
            # FATxx File::Basename module file system bug workaround
            $t =~ s|:[\\/]([^\\/]*\Z)|:/../$1|;
            
            # get abs path for t for storage
            my $t_dir = dirname( $t );
            my $t_base = basename( $t );
            my $abs_t = abs_path( $t_dir );    
            my $full_t = "$abs_t/$t_base";
            $t = $full_t;
            
            $handles_to_names{$fh} = $t 
                          unless($handles_to_names{$fh});
            
        }
        else { die("syntax error in File::ManualFlock::FlockOverride open for $spec: $!"); }
    }    
    return $retval;    
}

#-------------------------------------------------------------------#

# override perl close
sub close (*) {
    my $fh = shift || select ; # for close(FH);  or  close;
    if($handles_to_names{$fh}) { 
      
      # get close lock handle (clh) from %lh_keep_alive
      
      my $clh = $lh_keep_alive{$fh};
      if ( $clh ) { $clh->free_lock };
    }
    no strict 'refs';
    return CORE::close(*$fh);  # delegate rest of close to regular close
    use strict 'refs';
}

#-------------------------------------------------------------------#

END
{
  if ( defined %lh_keep_alive )
  { 
    foreach my $lhk ( keys %lh_keep_alive )
    {
      #print "lh: $lhk\n";
      #print "val: $lh_keep_alive{$lhk}\n";
      $lh_keep_alive{$lhk}->free_lock;
    }
  }
}

#======================================#
# pod                                  #
#===================================================================#

=item

=head1 NAME

File::ManualFlock::FlockOverride - 
    overrides flock, if implemented on system, or provides manual file locking
    for systems without standard flock function (Win95/98/??); uses File::ManualFlock
    to lock files; overrides flock, open, and close functions in the calling package
    
=head1 SYNOPSIS
    
    use File::ManualFlock::FlockOverride qw( :flock_override );
    
    open( $fh, ">$filepath" );
    my $lock = (LOCK_SH|LOCK_NB);
    my $fl_result = flock( $fh, $lock );
    close( $fh );
    
    See File::ManualFlock docs or flock() docs for more details regarding the possible 
    values for $lock.

=head1 DESCRIPTION

This module allows the File::ManualLock module to be used as a substitute for flock.

Mflock, like flock, is an advisory locking mechanism.  Mflock can be
used as a substitute for flock, but it will not detect files locked
with flock.  Likewise, flock will not detect files locked with mflock.  
Thus, while File::ManualFlock::FlockOverride offers a 'flock'
function that when used will override the standard flock and provide
the same interface, the two locking methods cannot be used
interchangeably. You must choose one or the other and go with it.

=head1 NOTES

Even though the flock function provided by this module is simply a wrapper
around mflock method provided by the File::ManualLock module,
its default behavior is different in order to match up with the standard 
flock function's behavior (on systems where it is implemented.)  Thus, the 
flock function provided here will not clobber expired locks and is blocking
by default.

This behavior is given by the line in the function File::ManualLock::FlockOverride::flock
that calls the File::ManualLock::mflock method as follows:

  $lh_keep_alive{$fh} = $mf->mflock( $filepath, $lock, MFL_INFINITE, MFL_INFINITE );

You can modify the $max_wait and $expire params in the code in order to achieve
another desired default behavior.  See the File::ManualFlock docs for additional
details on the mflock method that it provides.

=head1 LICENSE

Same as Perl.

=head1 CREDIT

Much of the techniques and code in this module that allows these functions
to override the core functions is borrowed from William Herrera's File::FlockDir
module.  However, the underlying flock code was written from scratch.

=head1 AUTHOR

Bill Catlan, E<lt>wcatlan@cpan.orgE<gt>

=cut

#===================================================================#
1;

