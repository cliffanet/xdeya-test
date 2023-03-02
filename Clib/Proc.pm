package Clib::Proc;

use strict;
use warnings;

use POSIX qw(WNOHANG setsid);

##############################################################################
####    При использовании use Clib::Proc можно указать ряд параметров:
=pod
        script0/script1/.../script5 - Определить переменную ROOT исходя из того,
                    что вызываемый скрипт лежит в корне/подпапке/.../подуровне5
    
        Для корректной работы scriptX надо сделать:
            ln -s /usr/local/bin/perl /usr/bin/perl
            ln -s /home/clib/Clib /usr/local/lib/perl5/site_perl/Clib
            или:
            mkdir /usr/local/lib/perl5/site_perl/Clib
            ln -s /home/clib/Clib/Proc.pm /usr/local/lib/perl5/site_perl/Clib/Proc.pm
    
        lib - Сделать use lib для папки ROOT/lib
        
        const/constutf8=basepath - Загрузить константы через Clib::Const,
                    при отсутствии basepath используется корень, если он определён
                    
        pid=file - Использовать pidfile, если подгружен Clib:::Const,
                    возможно использование констант в формате $varname->subvar
=cut
my ($root, $scriptdir);
my @lib = ();
my $import_count = 0;
my $pidobj;
sub import {
    my $pkg = shift;
    
    my $root1 = $root;
    
    while (@_) {
        my $p = shift() || next;
        
        if ($p eq 'strict') {
            
            no warnings;
            ${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55";
            $^H |= 0x00800000; # use utf8;
            $^H |= 0x00000602; # use strict;
        }
        elsif ($p eq 'strict8') {
            
            no warnings;
            ${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55";
            $^H |= 0x00000602; # use strict;
        }
        
        elsif ($p =~ /^script([0-9])$/) {
            $root1 = root_by_script($1);
        }
        elsif ($p =~ /^lib([0-9])$/) {
            $root1 = root_by_lib($1);
        }
        
        elsif ($p =~ /^root[\-=#@](.+)$/) {
            $root1 = $1 || undef;
        }
        
        elsif ($p eq 'lib') {
            $root1 || die "Can't `use lib` - ROOT not defined";
            my $lib = $root1.'/lib';
            eval 'use lib "'.$lib.'";';
            unshift(@lib, $lib) unless grep { $_ eq $lib } @lib;
        }
        
        elsif ($p =~ /^const(?:[\-=#@](.+))?$/) {
            my $base = $1 || '';
            $base = $root1 . ($base ? '/'.$base : '') if $root1 && ($base !~ /^\//);
            $base || die 'Can\'t load `const` - ROOT or base dir not defined';
            require Clib::Const;
            Clib::Const::load('', $base);
        }
        
        elsif ($p =~ /^constutf8(?:[\-=#@](.+))?$/) {
            my $base = $1 || '';
            $base = $root1 . ($base ? '/'.$base : '') if $root1 && ($base !~ /^\//);
            $base || die 'Can\'t load `const` - ROOT or base dir not defined';
            require Clib::Const;
            Clib::Const::load('', $base, ':utf8');
        }
        
        elsif ($p =~ /^pid[\-=#@](.+)$/) {
            pidfile($1);
        }
        
        elsif ($p =~ /^param(?:script)?$/i) {
            my $pkg = caller(0);
            my $s = "push \@$pkg\::ISA, 'Clib::Proc::ParamScript'
                        unless grep { \$_ eq 'Clib::Proc::ParamScript' } \@$pkg\::ISA;";
                        eval $s;
        }
        
        else {
            die 'Unknown use-parameter \''.$p.'\'';
        }
    }
    
    if ($root1) {
        my $callpkg = caller(0);
        no warnings 'once';
        no strict 'refs';
        my $r2 = eval "\$${callpkg}::pathRoot";
        if (!defined($r2)) {
            *{"${callpkg}::ROOT"} = sub { $root1 };
            my $pathRoot = $root1;
            *{"${callpkg}::pathRoot"} = \$pathRoot;
            *{"${callpkg}::SCRIPTDIR"} = \&SCRIPTDIR;
        }
        
        $root = $root1 if !defined($root);
    }
    
    $import_count ++;
}

sub ROOT { $root || die "ROOT not defined"; $root }
sub setroot { $root = shift() || undef; }
sub SCRIPTDIR { $scriptdir }
sub lib { @lib }

sub lib_push { unshift @lib, @_; }
sub lib_pop { shift @lib; }

sub root_by_script {
    my ($level) = @_;
    
    require Cwd;
    require File::Basename;
    my $dir = File::Basename::dirname( Cwd::abs_path($0) );
    $scriptdir = $dir;
    
    $level ||= 0;
    while ($dir && ($level > 0)) {
        $dir = File::Basename::dirname( $dir );
        $level --;
    }
    
    return $dir || undef;
}

sub root_by_lib {
    my ($level, $pkg) = @_;
    
    if (!$pkg) {
        my $n = 0;
        $pkg = caller($n);
        $pkg = caller(++$n) if $pkg eq __PACKAGE__;
    }
    
    $pkg =~ s/\:\:/\//g;
    $pkg .= '.pm' unless $pkg =~ /\.pm$/;
    
    my $dir = $INC{$pkg} || return;
    $dir = File::Basename::dirname( Cwd::abs_path($dir) );
    
    $level ||= 0;
    while ($dir && ($level > 0)) {
        $dir = File::Basename::dirname( $dir );
        $level --;
    }
    
    return $dir || undef;
}

sub pidfile {
    my ($file, $err_running, $err_pidfile) = @_;
    $file || die "`pidfile` argumet needed";

    $err_running ||= sub {
        print sprintf('Already running on PID %s', $_[0])."\n";
    };
    $err_pidfile ||= sub {
        print sprintf('Can\'t make PID-file `%s`: %s', $_[0], $_[1]||'<-unknown->')."\n";
    };
    
    $pidobj = _pidfile($file, $err_running, $err_pidfile) || exit -1;
}

sub _pidfile {
    my ($file, $err_running, $err_pidfile) = @_;
    $file || return;
    
    $file = Clib::Const::parse($file) if ($file =~ /\$/) && $INC{'Clib/Const.pm'};
    $file = $root . '/'. $file if $root && ($file !~ /^\//);
    
    my $pid = Clib::Proc::PidFile->isrun($file);
    if ($pid) {
        $err_running->($pid) if ref($err_running) eq 'CODE';
        return 0;
    }
    
    my $obj = Clib::Proc::PidFile->makeobj($file);
    if (!$obj) {
        $err_pidfile->($file, $!, $$) if ref($err_pidfile) eq 'CODE';
        return;
    }
    
    $obj;
}

sub forkinit {
    
    # Работу со списком term надо отсюда убрать, т.к. есть событие onterm
    my $f = { chld => {}, term => [] };
    bless $f, 'Clib::Proc::Fork';
    
    $SIG{CHLD} = sub {
        while ( defined(my $pid = waitpid(-1, WNOHANG)) ) {
            last unless $pid > 0;
            my $chld = delete $f->{chld}->{$pid} || next;
            #push @{ $f->{term} }, $chld;
            $f->{onterm}->(%$chld) if $f->{onterm};
        }
    };
    
    return $f;
}

sub daemon {
    #my $class = shift;
    my %p = @_;
    
    my $pidfile = $p{pidfile}||$p{pid_file};
    if ($pidfile) {
        $pidfile = Clib::Const::parse($pidfile) if ($pidfile =~ /\$/) && $INC{'Clib/Const.pm'};
        $pidfile = $root . '/'. $pidfile if $root && ($pidfile !~ /^\//);
    
        my $pid = Clib::Proc::PidFile->isrun($pidfile);
        if ($pid) {
            my $piderr = $p{piderr}||$p{pid_err}||$p{piderror}||$p{pid_error}||
                        $p{pidrun}||$p{pid_run}||$p{pidrunning}||$p{pid_running}||
                        sub {
                            print sprintf('Already running on PID %s', $_[0])."\n";
                        };
            $piderr->($pid) if ref($piderr) eq 'CODE';
            return 0;
        }
    }
    
    if (!$p{no} && !$p{nodaemon} && !$p{nodaemonize} && !$p{debug}) {
        my $pid = fork;
        defined($pid) || return;
        if ($pid) {
            POSIX::_exit(0);
            return 0;
        }
        
        my $umask = umask;
        
        die "Cannot detach from controlling terminal" if POSIX::setsid() < 0;
        if ($p{uid}) {
            POSIX::setuid($p{uid}) || die("Can't set uid[$p{uid}]: $!");
        }
        if ($p{gid}) {
            POSIX::setgid($p{gid}) || die("Can't set gid[$p{gid}]: $!");
        }
        
        close STDIN;
        close STDOUT;
        close STDERR;
        
        open( STDIN,  "</dev/null" );
        open( STDOUT, "+>/dev/null" );
        open( STDERR, "+>/dev/null" );
        
        umask $umask;
        
        delete $ENV{TERM};
    }
    
    if ($pidfile) {
        my $pf = Clib::Proc::PidFile->makeobj($pidfile) || die "Can't make pidfile `$pidfile`: $!";
        sigint(sub { $pf->destroy() });
    }
    
    if (my $name = $p{procname}||$p{proc}||$p{name}) {
        $0 = $name;
    }
    
    return 1;
}

my @sigint = ();
sub sigint {
    @_ || return @sigint;
    
    my $set = @sigint ? 0 : 1;
    
    push @sigint, @_;
    
    if ($set) {
        $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
                $_->() foreach @sigint;
            };
    }
    
    return @sigint;
}

sub paramscript_cmdref {
    @ARGV || return;
    
    my ($method) = @ARGV;
    $method || return; #undef;
    
    my $n = 0;
    my $callpkg = caller($n);
    $callpkg = caller(++$n) while $callpkg eq __PACKAGE__;
    $callpkg || return;
    
    no strict 'refs';
    
    if (@Clib::Proc::ParamScript::cmd) {
        # Новый фильтр доступных команд через аттрибут : cmd
        $method = "${callpkg}::$method";
        exists(&$method) || return undef;
        my $ref = \&$method;
        
        return undef
            unless grep { $_->{ref} eq $ref } @Clib::Proc::ParamScript::cmd;
    }
    else {
        # новый фильтр команд через префикс cmd_
        $method = "${callpkg}::cmd_$method";
        exists(&$method) || return undef;
    }
    
    return \&$method;
}

sub paramscript_cmdall {
    my $n = 0;
    my $callpkg = caller($n);
    $callpkg = caller(++$n) while $callpkg eq __PACKAGE__;
    $callpkg || return;
    
    no strict 'refs';
    
    if (@Clib::Proc::ParamScript::cmd) {
        # Новый фильтр доступных команд через аттрибут : cmd
        # Этим же способом список получается отсортированный
        my %ref = %{*{"$callpkg\::"}};
        my %name = (); # Будем получать хеш "ссылка => имя функции"
        foreach my $key (keys %ref) {
            $key || next;
            my $val = $ref{$key};
            defined($val) || next;
            local(*ENTRY) = $val;
            my $ref = *ENTRY{CODE} || next;
            $name{ $ref } = $key;
        }
        return
            map { $name{ $_->{ref} } }
            grep { $_->{pkg} eq $callpkg }
            @Clib::Proc::ParamScript::cmd;
    }
    
    # Старый фильтр доступных команд через префикс cmd_
    # тут никак не получить сортировку кроме как через MODIFY_CODE_ATTRIBUTES
    return
        map { s/^cmd_// ? $_ : () }
        grep { exists(&{"$callpkg\::$_"}) }
        keys %{ "$callpkg\::" };
}

sub paramscript_cmdarg {
    my $cmd = shift;
    
    my $n = 0;
    my $callpkg = caller($n);
    $callpkg = caller(++$n) while $callpkg eq __PACKAGE__;
    $callpkg || return;
    
    no strict 'refs';
    my $f = *{"$callpkg\::$cmd"};
    local(*ENTRY) = $f;
    my $ref = *ENTRY{CODE} || next;
    
    my ($c) = grep { $_->{ref} eq $ref } @Clib::Proc::ParamScript::cmd;
    $c || return;
    
    return @{ $c->{arg}||[] };
}

package Clib::Proc::PidFile;

sub isrun {
    my ($class, $file) = @_;

    return 0 unless
        -e $file && 
        -r $file;
    
    my $fh;
    open($fh, $file) || return;
    my $pid = <$fh>;
    close $fh;
    
    $pid || return;
    $pid =~ s/\s+$//;
    return if !$pid || $pid !~ /^\d+$/;
    
    return (kill 0, $pid) ? $pid : 0;
}

sub make {
    my ($class, $file, $pid) = @_;
    $pid ||= $$;
    
    my $fh;
    open($fh, '>', $file) || return;
    print $fh $pid."\n";
    close $fh;
    
    return $pid;
}

sub makeobj {
    my ($class, $file, $pid) = @_;
    
    $pid = make($class, $file, $pid) || return;
    
    my $pf = { file => $file, pid => $pid };
    bless $pf, $class;
    
    return $pf;
}

sub destroy {
    my $self = shift() || return;
    
    # Возможно после форка мы уже поменяли pid,
    # В этом случае не трогаем файл - его удалит тот процесс, который его создал
    return if $self->{pid} && ($self->{pid} != $$);
    
    $self->{file} || return;
    unlink $self->{file};
    delete $self->{file};
}

DESTROY { destroy(@_) }


package Clib::Proc::Fork;

sub chld { %{ shift()->{chld}||{} } }
sub child { %{ shift()->{chld}||{} } };
sub childs { %{ shift()->{chld}||{} } };

sub chldcnt { scalar keys %{ shift()->{chld}||{} } }
sub childcount { scalar keys %{ shift()->{chld}||{} } };

sub ischld { shift()->{ischld} };
sub ischild { shift()->{ischld} };

# Работу со списком term надо отсюда убрать, т.к. есть событие onterm (оставляем, пока есть код, где это используется)
sub term { shift @{ shift->{term} } }
sub terminated { shift @{ shift->{term} } }
sub onterm {
    my $self = shift;
    
    if (@_) {
        my $hnd = shift;
        if (ref($hnd) eq 'CODE') {
            $self->{onterm} = $hnd;
        }
        else {
            delete $self->{onterm};
        }
    }
    
    return $self->{onterm};
}

sub fork {
    my $self = shift;
    
    my $pid = fork;
    defined($pid) || return;
    
    if ($pid) {
        $self->{chld}->{$pid} = { @_, pid => $pid };
        return $pid;
    }
    else {
        $self->{ischld} = 1;
        delete $self->{chld};
        delete $self->{term};
        return $$;
    }
    
    undef;
}

sub termall {
    my $self = shift;
    my $destroy_chld = shift();
    
    my @pid =
        sort { $a <=> $b }
        keys %{ $self->{chld} || {} };
    
    foreach my $pid (@pid) {
        my $chld = $destroy_chld?
            delete($self->{chld}->{$pid}) :
            $self->{chld}->{$pid};
        $chld || next;
        kill TERM => $pid;
    }
    
    1;
}

DESTROY {
    my $self = shift() || return;
    
    $self->termall(1);
}


package Clib::Proc::ParamScript;

use attributes;

our @cmd = ();

sub MODIFY_CODE_ATTRIBUTES{
    my ($pkg, $ref, @attr1) = @_;
 
    my @unknown = ();
    foreach (@attr1){
        my $name = $_;
        my $arg = undef;
        if ($name =~ /^([^\(]+)(\(.*\))$/) {
            $name = $1;
            $arg = eval "package $pkg; [$2];";
        }
        my $attr = lc $name;
        if (($attr eq 'cmd') && (ref($ref) eq 'CODE')) {
            push @cmd, { pkg => $pkg, ref => $ref, arg => $arg };
        }
        else {
            push @unknown, $_;
            next;
        }
    }
    return @unknown;
}

#==========================================================
#================================================== End ===
#==========================================================

1;
