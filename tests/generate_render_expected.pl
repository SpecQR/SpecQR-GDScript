use strict; use warnings; use JSON::PP; use Digest::SHA qw(sha256_hex);
use SpecQR::Render qw(:all);
my @cases;
my @sets=(
 [21,0,{margin=>0,scale=>1}], [21,1,{}], [21,2,{margin=>1,scale=>2,foreground=>'#1234',background=>'transparent'}],
 [25,0,{margin=>3,scale=>3,foreground=>'#01234567',background=>'#89abcdef'}],
 [177,1,{margin=>4,scale=>1}], [177,2,{margin=>0,scale=>2,foreground=>'WHITE',background=>'black'}],
 [21,0,{margin=>0,scale=>3,foreground=>'#abc',background=>'#def'}],
 [21,1,{margin=>3,scale=>5,foreground=>'#010101',background=>'#fefefe'}]
);
for my $set (@sets) { my($n,$pattern,$opts)=@$set;
 my $m=[map {my $y=$_; [map {my $x=$_; my $b=$pattern==0?($x+$y)%2==0:$pattern==1?(($x*3+$y*7)%11)<5:$x==$y||$x+$y==$n-1; $b?JSON::PP::true:JSON::PP::false} 0..$n-1]} 0..$n-1];
 my $pixels=to_pixels($m,$opts); my $png=to_png($m,$opts);my $svg=to_svg($m,$opts);
 push @cases,{size=>$n,pattern=>$pattern,options=>$opts,width=>$pixels->{width},pixelsSize=>length($pixels->{pixels}),pixelsSha256=>sha256_hex($pixels->{pixels}),pngSize=>length($png),pngSha256=>sha256_hex($png),svgSize=>length($svg),svgSha256=>sha256_hex($svg),pngUrlSha256=>sha256_hex(to_png_data_url($m,$opts)),svgUrlSha256=>sha256_hex(to_svg_data_url($m,$opts))};
}
print JSON::PP->new->canonical->pretty->encode({provenance=>'Generated from verified dependency-free Perl renderer using synthetic matrices',cases=>\@cases});
