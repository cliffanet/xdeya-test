package Clib::Const;

use strict;
use warnings;

my %const = ();
my $namespace = '';
my $error;

sub namespace {
    $namespace = shift() if @_;
    $namespace = '' unless defined $namespace;
    
    return $namespace;
}
sub error { $error }

sub import {
    my $pkg = shift;
    
    my $noimport = grep { $_ eq ':noimport' } @_;
    if ($noimport) {
        @_ = grep { $_ ne ':noimport' } @_;
        $noimport = 1;
    }
    my $utf8 = grep { $_ eq ':utf8' } @_;
    if ($utf8) {
        @_ = grep { $_ ne ':utf8' } @_;
        $utf8 = 1;
    }
    
    my $namespace = shift;
    $namespace = '' unless defined $namespace;
    
    if (!$const{$namespace}) {
        load($namespace, $utf8 ? (':utf8') : (), @_) || die $error;
    }
    
    $noimport || importer($namespace);
}

sub importer {
    my $namespace = @_ ? shift() : $namespace;
    $namespace = '' unless defined $namespace;
    
    my $callpkg = caller(0);
    $callpkg = caller(1) if $callpkg eq __PACKAGE__;
    my $getLocal = sub { _get($namespace, @_) };
    no strict 'refs';
    *{"${callpkg}::c"} = $getLocal;
    *{"${callpkg}::const"} = $getLocal;
}

sub load {
    my $namespace = shift;
    $namespace = '' unless defined $namespace;
    
    my $utf8 = grep { $_ eq ':utf8' } @_;
    if ($utf8) {
        @_ = grep { $_ ne ':utf8' } @_;
        $utf8 = 1;
    }
    my $root;
    @_ = grep {
            if (/^\:script([0-9])$/) {
                require Clib::Proc;
                $root = Clib::Proc::root_by_script($1);
                0;
            }
            elsif (/^\:lib([0-9])$/) {
                my $level = $1;
                require Clib::Proc;
                my $n = 0;
                my $pkg = caller($n);
                $pkg = caller(++$n) if $pkg eq __PACKAGE__;
                $root = Clib::Proc::root_by_lib($level, $pkg);
                0;
            }
            else {
                1;
            }
        } @_;
    
    my $base = shift() || '';
    
    delete $const{$namespace};
    namespace($namespace);
    
    if (!$base || ($base !~ /^\//)) {
        if (!$root) {
            my $n = 0;
            my $pkg = caller($n);
            $pkg = caller(++$n) if $pkg eq __PACKAGE__;
            no strict 'refs';
            $root = ${"${pkg}::pathRoot"};
        }
        $root = Clib::Proc::ROOT() if !$root && $INC{'Clib/Proc.pm'};
        if ($root) {
            $base = $root . ($base ? '/'.$base : '');
        }
    }
    
    #print "Const load: '$namespace' => $base\n";
    
    if (!$base) {
        $error = 'base dir not defined';
        return;
    }
    
    if ($_[0] && ($_[0] eq ':utf8')) {
        shift;
        $utf8 = 1;
    }
    
    my @file = ();
    
    if ($INC{'Clib/Proc.pm'} && (my $scriptdir = Clib::Proc::SCRIPTDIR())) {
        if (($scriptdir ne $base) && ($scriptdir ne "const/$base")) {
            push @file,
                { file => $scriptdir . '/' . 'const.conf', utf8 => $utf8 },
                { file => $scriptdir . '/' . 'const/const.conf', utf8 => $utf8 };
        }
    }
        
    push @file,
        { file => $base . '/' . 'const.conf', utf8 => $utf8 },
        { file => $base . '/' . 'const/const.conf', utf8 => $utf8 };
    
    if (@_) {
        foreach my $p (@_) {
            if ($p eq ':utf8') {
                $utf8 = 1;
                next;
            }
            push @file, { file => $base . '/' . "const/${p}.conf", key => $p, utf8 => $utf8 };
        }
    }
    elsif (-d $base . '/const') {
        my $dh;
        if (!opendir($dh, $base . '/const')) {
            $error = 'Can\'t read dir `'.$base.'/const`: '.$!;
            return;
        }
        while (defined(my $f = readdir $dh)) {
            next unless $f =~ /^[^\.].*\.conf$/;
            next unless -f $base . '/const/' . $f;
            push @file, { file => $base . '/const/' . $f, key => $f, utf8 => $utf8 };
        }
        closedir $dh;
    }
    
    if ($INC{'Clib/Proc.pm'} && (my $scriptdir = Clib::Proc::SCRIPTDIR())) {
        if (($scriptdir ne $base) && ($scriptdir ne "const/$base")) {
            push @file,
                { file => $scriptdir . '/' . 'redefine.conf', utf8 => $utf8 },
                { file => $scriptdir . '/' . 'const/redefine.conf', utf8 => $utf8 };
        }
    }
    
    push @file,
        { file => $base . '/' . 'redefine.conf', utf8 => $utf8 },
        { file => $base . '/' . 'const/redefine.conf', utf8 => $utf8 };
    
    foreach my $f (@file) {
        my $file = $f->{file};
        next unless -f $file;
        load_file($file, $namespace, $f->{key}, $f->{utf8}) || return;
    }
    
    return $const{$namespace} ||= {};
}

sub load_file {
    my ($file, $namespace, $key, $utf8) = @_;
    
    if (!$file) {
        $error = '$file not defined';
        return;
    }
    
    my $fh;
    if (!open($fh, $file)) {
        $error = 'Can\'t read file `'.$file.'`: '.$!;
        return;
    }
    
    local $/ = undef;
    my $code = <$fh>;
    close $fh;
    
    if (!$code) {
        $error = 'File `'.$file.'` is empty';
        return;
    }
    
    $utf8 = $utf8 ? 'use utf8; ' : '';
    my @c = eval $utf8.'('.$code.')';
    if ($@) {
        $error = 'Can\'t read const file \''.$file.'\': ' . $@;
        return;
    }

    if ($INC{'Clib/Proc.pm'} && (my $root = Clib::Proc::ROOT())) {
        unshift @c, ROOT => $root;
    }
    
    my $const = ($const{$namespace} ||= {});
    if (defined $key) {
        delete($const->{$key}) if exists($const->{$key}) && (ref($const->{$key}) ne 'HASH');
        $const->{$key} ||= {};
    }
    if (%$const) {
        _redefine($const, @c);
    }
    else {
        %$const = @c;
    }
    
    undef $error;
    
    $const;
}

sub _redefine {
    my ($c, %h) = @_;
    
    foreach my $k (keys %h) {
        my $v = $h{$k};
        
        if (ref($v) eq 'HASH') {
            _redefine($c->{$k}||={}, %$v);
        }
        elsif (defined $v) {
            $c->{$k} = $v;
        }
        else {
            delete $c->{$k};
        }
    }
    
    1;
}

sub _get {
    my $namespace = shift;
    $namespace = '' unless defined $namespace;
    
    my $c = ($const{$namespace} ||= {});
    while (@_ && defined($c)) {
        my $k = shift;
        $c = ref($c) eq 'ARRAY' ? $c->[$k] : $c->{$k};
    }
    $c;
}
sub get { _get($namespace, @_) }

sub bystr {
    my $path = shift;
    $path || return;
    
    return get(split /\-\>?/, $path);
}
sub parse {
    my $str = shift;
    $str || return $str;
    
    $str =~ s/\$([a-zA-Z0-9_]+(\-\>?[a-zA-Z0-9_]+)*)/bystr($1)/ge;
    
    return $str;
}

1;
