package CSG::Mapper::Command::show;

use CSG::Mapper -command;
use CSG::Base qw(formats);
use CSG::Constants;
use CSG::Mapper::DB;
use CSG::Mapper::Job;

my $schema = CSG::Mapper::DB->new();

sub opt_spec {
  return (
    ['info',      'display basic job info'],
    ['meta-id=i', 'job meta id'],
    ['step=s',    'display results for a given step (e.g. bam2fastq, align)'],
    ['state=s',   'display results for a given state (e.g. submitted, requested, failed)'],
    ['stale',     'find any jobs that are no longer queued but still in a running state (i.e. started, submitted)'],
    [
      'format=s',
      'output format (valid format: yaml|txt) [default: yaml]', {
        default   => 'yaml',
        callbacks => {
          regex => sub {
            shift =~ /yaml|txt/;
          }
        }
      }
    ]
  );
}

sub validate_args {
  my ($self, $opts, $args) = @_;

  if ($opts->{state}) {
    my $state = $schema->resultset('State')->find({name => $opts->{state}});
    unless ($state) {
      $self->usage_error('invalid state');
    }

    $self->{stash}->{state} = $state;
  }

  if ($opts->{step}) {
    my $step = $schema->resultset('Step')->find({name => $opts->{step}});
    unless ($step) {
      $self->usage_error('invalid step');
    }

    $self->{stash}->{step} = $step;
  }
}

sub execute {
  my ($self, $opts, $args) = @_;

  if ($opts->{info}) {
    my $meta = $schema->resultset('Job')->find($opts->{meta_id});
    return $self->_info($meta, $opts->{format});
  }

  if ($opts->{stale}) {
    return $self->_stale();
  }

  if ($opts->{state}) {
    my $build = $self->app->global_options->{build};
    my $state = $self->{stash}->{state};
    my $step  = $self->{stash}->{step};

    for my $result ($schema->resultset('ResultsStatesStep')->current_results_by_step_state($build, $step->name, $state->name)) {
      say $result->result->status_line();
    }
  }
}

sub _info {
  my ($self, $meta, $format) = @_;

  my $info = {
    sample => {
      id        => $meta->result->sample->id,
      sample_id => $meta->result->sample->sample_id,
      center    => $meta->result->sample->center->name,
      study     => $meta->result->sample->study->name,
      pi        => $meta->result->sample->pi->name,
      host      => $meta->result->sample->host->name,
      filename  => $meta->result->sample->filename,
      run_dir   => $meta->result->sample->run_dir,
      state     => $meta->result->current_state,
      step      => $meta->result->current_step,
      build     => $meta->result->build,
      fullpath  => $meta->result->sample->fullpath,
    },
    job => {
      id        => $meta->id,
      job_id    => $meta->job_id,
      result_id => $meta->result_id,
      cluster   => $meta->cluster,
      procs     => $meta->procs,
      memory    => $meta->memory,
      walltime  => $meta->walltime,
      node      => $meta->node,
      delay     => $meta->delay,
      submitted => ($meta->submitted_at) ? $meta->submitted_at->ymd . $SPACE . $meta->submitted_at->hms : $EMPTY,
      created   => $meta->created_at->ymd . $SPACE . $meta->created_at->hms,
    }
  };

  if ($format eq 'txt') {
    print Dumper $info;
  } else {
    print Dump($info);
  }

  return;
}

sub _stale {
  my ($self) = @_;

  my $step    = $self->{stash}->{step};
  my $cluster = $self->app->global_options->{cluster};
  my $build   = $self->app->global_options->{build};
  my $results = $schema->resultset('ResultsStatesStep')->current_results_by_step($build, $step->name);

  for my $result ($results->all) {
    next unless $result->state->name eq 'started';
    next unless $result->job->cluster eq $cluster;

    my $job = CSG::Mapper::Job->new(
      cluster => $cluster,
      job_id  => $result->job->job_id
    );

    my $job_state = $job->state;
    next if $job_state eq 'running';
    say $result->result->status_line . 'JOBID: ' . $job->job_id . ' JOBSTATUS: ' . $job_state;
  }
}

1;

__END__

=head1

CSG::Mapper::Command::show - show remapping jobs
