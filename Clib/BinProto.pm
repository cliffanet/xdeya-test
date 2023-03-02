package Clib::BinProto;

use Clib::strict;

use POSIX 'round';

####################
# Каждая структура упаковывается по выбранному правилу
# Сначала всегда 1 байт заголовка,
# s - код команды (int), следующий за заголовком (1байт)
# потом два байта - полная длина данных (без учёта двух байт заголовка)
#
# Типы переменных
# C - 1-байтовое целое
# n - 2-байтовое целое
# N - 4-байтовое целое
# c - 1-байтовое знаковое
# i - 2-байтовое знаковое
# I - 4-байтовое знаковое
# v - IP v4 адрес
# T - DateTime
# t - DateTime + в конце 1/100 секунды
# f - %0.2float
# D - double (64bit)
# x - hex16
# X - hex32
# H - hex64
# a - символ (строка в 1 байт)
# add - строка фиксированной длины, ограниченная dd символами
# пробел - один зарезервированный байт (без привязки к ключу)
# S - динамическая строка, где длина строки - 2 байта
# s - динамическая строка, где длина строки - 1 байт
# 

sub new {
    my $class = shift() || return;
    
    my $self = {
    };
    
    bless $self, $class;
    
    $self->init(@_);
    
    return $self;
}

sub error {
    my $self = shift;
    
    if (@_) {
        my $s = shift;
        $s = sprintf($s, @_) if @_;
        push @{ $self->{error}||=[] }, $s;
    }
    
    my $err = $self->{error}||[];
    
    return
        wantarray ?
            @$err :
        @$err ?
            $err->[scalar(@$err)-1] :
            ();
}

sub errclear {
    my $self = shift;
    
    $self->{error} = [];
}

sub init {
    my $self = shift;
    
    $self->{hdr} = shift() || return;
    
    $self->errclear();
    delete $self->{pack};
    delete $self->{unpack};
    delete $self->{code2s};
    
    $self->add(%$_) foreach @_;
    
    return @{ $self->{error}||[] } ? 0 : 1;
}

sub add {
    my $self = shift;
    my %p = @_;
    
    $p{pk} ||= '';
    $p{key} ||= '';
    # элемент протокола (одномерных хэш ключ-значение)
    my @pk = split //, $p{pk};        # коды упаковки ключа элемента
    my @key = split /,/, $p{key};     # ключи элемента для упаковки
    
    # Для каждого ключа элемента получим набор функций для упаковки и набор функций для распаковки
    my $i = 0;
    my @pack = ();
    my @unpack = ();
    while (@pk) {
        $i ++;
        my $pk = shift @pk;
        my $key;
        if ($pk ne ' ') {
            $key = shift @key;
            if (!$key) {
                $self->error('[code=%s, key=%d] unknown key of element', $p{code}, $i);
            }
        }
        
        if (($pk eq 'C') || ($pk eq 'c')) {
            push @pack, sub {
                return
                    1,
                    CORE::pack($pk, defined($_[0]->{$key}) ? $_[0]->{$key} : 0);
            };
            push @unpack, sub {
                my $v = CORE::unpack($pk, $_[0]);
                return
                    1,
                    defined($v) ? ($key => $v) : ();
            };
        }
        
        elsif ($pk eq 'n') {
            push @pack, sub {
                return
                    2,
                    CORE::pack('n', defined($_[0]->{$key}) ? $_[0]->{$key} : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('n', $_[0]);
                return
                    2,
                    defined($v) ? ($key => $v) : ();
            };
        }
        
        elsif ($pk eq 'N') {
            push @pack, sub {
                return
                    4,
                    CORE::pack('N', defined($_[0]->{$key}) ? $_[0]->{$key} : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('N', $_[0]);
                return
                    4,
                    defined($v) ? ($key => $v) : ();
            };
        }
        
        elsif ($pk eq 'i') {
            push @pack, sub {
                return
                    2,
                    CORE::pack('n', defined($_[0]->{$key}) ? $_[0]->{$key} : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('n', $_[0]);
                $v -= 0x10000 if defined($v) && ($v > 0x7fff);
                return
                    2,
                    defined($v) ? ($key => $v) : ();
            };
        }
        
        elsif ($pk eq 'I') {
            push @pack, sub {
                return
                    4,
                    CORE::pack('N', defined($_[0]->{$key}) ? $_[0]->{$key} : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('N', $_[0]);
                if (defined($v) && ($v > 0x7fffffff)) {
                    $v -= 0xffffffff;
                    $v--;
                }
                return
                    4,
                    defined($v) ? ($key => $v) : ();
            };
        }
        
        elsif ($pk eq 'v') {
            push @pack, sub {
                return
                    4,
                    CORE::pack('C4', defined($_[0]->{$key}) ? split(/\./, $_[0]->{$key}) : (0,0,0,0));
            };
            push @unpack, sub {
                my @ip = CORE::unpack('C4', $_[0]);
                return
                    4,
                    (@ip == 4) && defined($ip[3]) ? ($key => join('.',@ip)) : ();
            };
        }
        
        elsif ($pk eq 'T') {
            push @pack, sub {
                my $dt = $_[0]->{$key};
                return
                    8,
                    CORE::pack('nCCCCCC',
                        $dt && ($dt =~ /^(\d{2,4})-(\d{1,2})-(\d{1,2}) (\d{1,2})\:(\d{1,2})\:(\d{1,2})$/) ?
                            ((length($1) < 3 ? $1+2000 : int($1)), int($2), int($3),  int($4), int($5), int($6),  0) :
                            (0,0,0, 0,0,0, 0)
                    );
            };
            push @unpack, sub {
                my @dt = CORE::unpack('nCCCCCC', $_[0]);
                return 
                    8,
                    (@dt == 7) && defined($dt[6]) ?
                        ($key => sprintf("%04d-%02d-%02d %d:%02d:%02d", @dt[0..5])) :
                        ();
            };
        }
        
        elsif ($pk eq 't') {
            push @pack, sub {
                my $dt = $_[0]->{$key};
                return
                    8,
                    CORE::pack('nCCCCCC',
                        $dt && ($dt =~ /^(\d{2,4})-(\d{1,2})-(\d{1,2}) (\d{1,2})\:(\d{1,2})\:(\d{1,2})(?:\.(\d\d))?$/) ?
                            (($1 < 100 ? $1+2000 : int($1)), int($2), int($3),  int($4), int($5), int($6), int($7||0)) :
                            (0,0,0, 0,0,0, 0)
                    );
            };
            push @unpack, sub {
                my @dt = CORE::unpack('nCCCCCC', $_[0]);
                return 
                    8,
                    (@dt == 7) && defined($dt[6]) ?
                        ($key => sprintf("%04d-%02d-%02d %d:%02d:%02d.%02d", @dt)) :
                        ();
            };
        }
        
        elsif ($pk eq 'f') {
            push @pack, sub {
                return
                    2,
                    CORE::pack('n', defined($_[0]->{$key}) ? POSIX::round($_[0]->{$key} * 100) : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('n', $_[0]);
                $v -= 0x10000 if defined($v) && ($v > 0x7fff);
                return
                    2,
                    defined($v) ? ($key => sprintf('%0.2f', $v/100)) : ();
            };
        }
        
        elsif ($pk eq 'D') {
            push @pack, sub {
                my $v = defined($_[0]->{$key}) ? $_[0]->{$key} : 0;
                my $i = int $v;
                my $d = abs($v - $i);
                return
                    8,
                    CORE::pack('NN', $i, int($d * 0xffffffff));
            };
            push @unpack, sub {
                my ($i, $d) = CORE::unpack('NN', $_[0]);
                return 8 if !defined($i) || !defined($d);
                if ($i > 0x7fffffff) {
                    $i -= 0xffffffff;
                    $i--;
                }
                $d *= -1 if $i < 0;
                return
                    8,
                    $key => $i+($d/0xffffffff);
            };
        }
        
        elsif ($pk eq 'x') {
            push @pack, sub {
                return
                    2,
                    CORE::pack('n', defined($_[0]->{$key}) ? hex($_[0]->{$key}) : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('n', $_[0]);
                return
                    2,
                    defined($v) ? ($key => sprintf('%04x', $v)) : ();
            };
        }
        
        elsif ($pk eq 'X') {
            push @pack, sub {
                return
                    4,
                    CORE::pack('N', defined($_[0]->{$key}) ? hex($_[0]->{$key}) : 0);
            };
            push @unpack, sub {
                my ($v) = CORE::unpack('N', $_[0]);
                return
                    4,
                    defined($v) ? ($key => sprintf('%08x', $v)) : ();
            };
        }
        
        elsif ($pk eq 'H') {
            push @pack, sub {
                my @h = ();
                if (defined $_[0]->{$key}) {
                    my $hex64 = $_[0]->{$key};
                
                    my $l = 0;
                    if ($hex64 =~ s/([0-9a-fA-F]{1,8})$//) {
                        $l = hex $1;
                    }
                    $hex64 = 0 if $hex64 eq '';
                    @h = (hex($hex64), $l);
                }
                else {
                    @h = (0,0);
                }
                
                return
                    8,
                    CORE::pack('NN', @h);
            };
            push @unpack, sub {
                my @h = CORE::unpack('NN', $_[0]);
                return
                    8,
                    (@h == 2) && defined($h[1]) ? ($key => sprintf('%08x%08x', @h)) : ();
            };
        }
        
        elsif ($pk eq ' ') {
            my $len = 1;
            while (@pk && ($pk[0] eq ' ')) {
                shift @pk;
                $len++;
            }
            push @pack, sub {
                return
                    $len,
                    CORE::pack('C' x $len, map { 0 } 1 .. $len);
            };
            push @unpack, sub { return $len; };
        }
        
        elsif ($pk eq 'a') {
            my @l = ();
            push(@l, shift(@pk)) while @pk && ($pk[0] =~ /^\d$/);
            my $l = @l ? join('', @l) : 1;
            
            # Какой-то непонятный глюк с a/Z параметрами
            # Если использовать aXX, то на тесте работает всё нормально,
            # а в боевом сетевом трафике почему-то не удаляются терминирующие нули при распаковке
            # С параметром Z такой проблемы нет, упаковка/распаковка - нормально,
            # Но параметр Z не умеет работать с одиночными символами
            my $pstr = $l > 1 ? 'Z'.$l : 'a';
            push @pack, sub {
                my $str = defined($_[0]->{$key}) ? $_[0]->{$key} : '';
                if (utf8::is_utf8($str)) {
                    utf8::downgrade($str);
                }
                return $l, CORE::pack($pstr, $str);
            };
            push @unpack, sub {
                my ($str) = CORE::unpack($pstr, $_[0]);
                $str = '' if defined($str) && ($l == 1) && ($str eq "\000");
                return $l, defined($str) ? ($key => $str) : ();
            };
        }
        
        elsif ($pk eq 's') {
            push @pack, sub {
                my $str = defined($_[0]->{$key}) ? $_[0]->{$key} : '';
                if (utf8::is_utf8($str)) {
                    utf8::downgrade($str);
                }
                my $l = length($str);
                if ($l > 255) {
                    $str = substr($str, 0, 255);
                    $l = 255;
                }
                
                return $l+1, CORE::pack('C', $l).$str;
            };
            push @unpack, sub {
                my ($l) = CORE::unpack('C', $_[0]);
                return (1) if !defined($l);
                return $l+1, $key => substr($_[0], 1, $l);
            };
        }
        
        elsif ($pk eq 'S') {
            push @pack, sub {
                my $str = defined($_[0]->{$key}) ? $_[0]->{$key} : '';
                if (utf8::is_utf8($str)) {
                    utf8::downgrade($str);
                }
                my $l = length($str);
                if ($l > 0xffff) {
                    $str = substr($str, 0, 0xffff);
                    $l = 0xffff;
                }
                
                return $l+2, CORE::pack('n', $l).$str;
            };
            push @unpack, sub {
                my ($l) = CORE::unpack('n', $_[0]);
                return (2) if !defined($l);
                return $l+2, $key => substr($_[0], 2, $l);
            };
        }
        
        else {
            $self->error('[code=%s, key=%d/%s] unknown pack code=%s', $p{code}, $i, $key, $pk);
        }
    }
    
    if (@key) {
        $self->error('[code=%s] keys without pack-code: %s', $p{code}, join(',', @key));
    }
    
    my $s = int $p{s};
    
    # Тепер формируем общие функции - упаковки и распаковки
    ($self->{pack}||={})->{ $p{code} } = sub {
        my $d = shift();
        my ($len, $data) = (0, '');
        foreach my $p (@pack) {
            my ($l, $s) = $p->($d);
            $len += $l;
            $data .= $s;
        }
            
        return CORE::pack('A1Cn', $self->{hdr}, $s, $len) . $data;
    };
    ($self->{unpack}||={})->{ $s } = sub {
        my $data = shift;
        my $len = shift;
        my @data = ();
        foreach my $p (@unpack) {
            my ($l, @d) = $p->($data);
            $len -= $l;
            $data .= $s;
            push @data, @d;
            $data = substr($data, $l, $len);
            last if $data eq '';
        }
        return @data, code => $p{code};
    };
    
    ($self->{code2s}||={})->{ $p{code} } = $p{s};
    
    1;
}

sub del {
    my $self = shift;
    my $code = shift() || return;
    
    my ($code2s, $pack, $unpack) = ($self->{code2s}||{}, $self->{pack}||{}, $self->{unpack}||{});
    exists($code2s->{ $code }) || return;
    
    my $s = delete $code2s->{ $code };
    delete $pack->{ $code };
    delete $unpack->{ $s };
    
    1;
}

sub pack {
    my $self = shift;
    $self->errclear();
    
    my $proto = $self->{pack} || {};
    
    my $data = '';
    my $n = 0;
    while (@_) {
        $n++;
        # Общая проверка входных данных
        my $code = shift;
        my $d = {};
        if (ref($code) eq 'HASH') {
            $d = $code;
            $code = $d->{code};
            if (!$code) {
                $self->error('pack[item#%d]: code undefined in hash-struc', $n);
                return;
            }
        }
        elsif (!ref($code)) {
            if (!$code) {
                $self->error('pack[item#%d]: code undefined', $n);
                return;
            }
            $d = shift() if @_;
            if (ref($d) ne 'HASH') {
                $self->error('pack[item#%d code%%%s]: not hash-struct', $n, $code);
                return;
            }
        }
        else {
            $self->error('pack[item#%d]: unknown data-type', $n);
            return;
        }
        
        # По какому элементу будем кодить
        my $pk = $proto->{$code};
        if (!$pk) {
            $self->error('pack[item#%d code%%%s]: element with unknown code', $n, $code);
            return;
        }
        
        $data .= $pk->($d);
    }
    
    return $data;
}

sub unpack {
    my $self = shift;
    $self->errclear();
    
    my $proto = $self->{unpack} || {};
    my $hdr = $self->{hdr};
    
    if (!defined($hdr) || (length($hdr) != 1)) {
        $self->error('unpack: Call with wrong header: %s', defined($hdr) ? $hdr : '-undef-');
        return;
    }
    
    if (utf8::is_utf8($_[0])) {
        utf8::downgrade($_[0]);
    }
    
    my $len = length($_[0]) || return [];
    my $n = 0;
    my $ret = [];
    while ($len >= 4) {
        my ($hdr1,$s,$l) = unpack 'A1Cn', substr($_[0], 0, 4);
        
        # Общая проверка протокола по заголовку
        if ($hdr1 ne $hdr) {
            $self->error('unpack[item#%d]: element with unknown proto (hdr: %s, mustbe: %s)', $n, $hdr1, $hdr);
            return;
        }
        
        # По какому протоколу будем распаковывать
        my $upk = $proto->{$s};
        if (!$upk) {
            $self->error('ppack[item#%d]: element with unknown code (s: 0x%02x)', $n, $s);
            return;
        }
        
        return $ret if $len < (4+$l);
        
        push @$ret, { $upk->(substr($_[0], 4, $l), $l) };
        return if $self->error();
        
        $len -= 4+$l;
        $_[0] = substr $_[0], 4+$l, $len;
    }
    
    return $ret;
}

1;
