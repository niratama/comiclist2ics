#!env perl
# vim:sts=4:sw=4:et

use 5.010;
use utf8;
use Encode::EUCJPMS;
use Encode;
use IO::String;
use LWP::UserAgent;
use Unicode::Normalize;
use Data::ICal;
use Data::ICal::Entry::Event;
use Time::Piece;
use Time::Seconds;

use Data::Dumper;

# day-publisher group line
my $re_pub = qr/^(?<day>[123]?[0-9０-９上中下])・(?<series>.*?)\s*〈(?<publisher>.*)〉/;
# item line
my $re_item = qr/^(?<title>.*?)\s*［(?<author>.*)］\s*(?<price>([０-９]+|未定))/;
# header/footer marker
my $re_hr = qr/^－+$/;

sub last_day_of_month {
    my ($year, $month) = @_;

    return Time::Piece->strptime("$year-$month-1", '%Y-%m-%d')->month_last_day;
}

sub parsecomictext {
    my ($year, $month, $text) = @_;
    my $io = IO::String->new($text);
    my @items;
    my %bme_day = (
        '上' => 10,
        '中' => 20,
        '下' => &last_day_of_month($year, $month),
    );
    # remove header
    my $hr_count = 4;
    while (my $line = $io->getline) {
        chomp($line);
        if ($line =~ $re_hr) {
            $hr_count -= 1;
            last if $hr_count == 0;
        }
    }
    # read all group
    while (my $line = $io->getline) {
        chomp($line);
        next if $line eq '';
        if ($line =~ $re_pub) { # day-publisher group
            my %info_pub = %+;
            foreach my $key (qw(day publisher series)) {
                $info_pub{$key} = NFKC($info_pub{$key});
            }
            # 上中下旬のときの処理
            if (exists($bme_day{$info_pub{day}})) {
                $info_pub{num_day} = $bme_day{$info_pub{day}};
            } else {
                $info_pub{num_day} = int($info_pub{day});
            }
            my $item_line = '';
            # read all item
            while ($line = $io->getline) {
                chomp($line);
                $line =~ s/^\s+//;
                $line =~ s/\s+$//;
                $item_line .= $line;
                last if $item_line eq '';
                if ($item_line =~ $re_item) {
                    my %info_item = (%+, %info_pub);
                    foreach my $key (qw(title author price)) {
                        $info_item{$key} = NFKC($info_item{$key});
                    }
                    $info_item{year} = $year;
                    $info_item{month} = $month;
                    push @items, \%info_item;
                    $item_line = '';
                }
            }
        } else {
            last if $line =~ $re_hr;
        }
    }
    $io->close;
    return @items;
}

my ($year, $month) = @ARGV;
my @items;
my $ua = LWP::UserAgent->new;
foreach my $part (qw(a b c)) {
    my $filename = sprintf('%04d%02d%s.txt', $year, $month, $part);
    if (-e $filename) {
        open my $fh, '<', $filename;
        my $utext;
        if ($fh) {
            local $/;
            my $text = <$fh>;
            $utext = Encode::decode('utf-8', $text);
            close $fh;
        }
        push @items, &parsecomictext($year, $month, $utext);
    } else {
        my $res = $ua->get('http://www.sm.rim.or.jp/~suzuki/comics/' . $filename);
        if ($res->is_success) {
            my $utext = $res->decoded_content(charset => 'cp51932');
            open my $fh, '>', $filename;
            if ($fh) {
                print $fh Encode::encode('utf-8', $utext);
                close $fh;
            }
            push @items, &parsecomictext($year, $month, $utext);
        }
    }
}

my $cal = Data::ICal->new;
$cal->add_properties(prodid => '-//ComlcList2iCal//JA');

my $itemno = 0;
for my $item (@items) {
    my $ev = Data::ICal::Entry::Event->new;
    my $d = Time::Piece->strptime(join('-', $item->{year}, $item->{month}, $item->{num_day}), '%Y-%m-%d');
    $ev->add_properties(
        summary => ($item->{title} . '/' . $item->{author}),
        dtstart => $d->strftime('%Y%m%d'),
        dtend => ($d + ONE_DAY)->strftime('%Y%m%d'),
        uid => sprintf('%04d%02d-%d', $item->{year}, $item->{month}, $itemno),
        description => sprintf("%d/%d/%s\n%s %s\n%s\n%s\n%s円", $item->{year}, $item->{month}, $item->{day}, $item->{publisher}, $item->{series}, $item->{title}, $item->{author}, $item->{price}),
    );
    # $ev->property('dtstart')->[0]->parameters({'VALUE' => 'DATE'});
    # $ev->property('dtend')->[0]->parameters({'VALUE' => 'DATE'});
    $cal->add_entry($ev);
    $itemno += 1;
}
print Encode::encode('utf-8', $cal->as_string);

1;

