use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'MIME::Xparser',
    'VERSION_FROM' => 'Xparser.pm', # finds $VERSION
    'dist'      => { 'COMPRESS' => 'gzip', 'SUFFIX' => 'gz' },
);
