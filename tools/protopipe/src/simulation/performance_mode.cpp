//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "performance_mode.hpp"

#include <chrono>
#include <regex>

#include "simulation/computation.hpp"
#include "simulation/executor.hpp"
#include "simulation/layers_data.hpp"
#include "utils/logger.hpp"
#include "utils/utils.hpp"

#include "opencv2/gapi/infer/ov.hpp"

class PerformanceMetrics {
public:
    PerformanceMetrics(const uint64_t elapsed, const std::vector<int64_t> latency, const std::vector<int64_t> seq_ids);
    friend std::ostream& operator<<(std::ostream& os, const PerformanceMetrics& metrics);

private:
    // TODO: avg, min, max statistics can be encapsulated.
    double avg_latency_ms;
    double min_latency_ms;
    double max_latency_ms;
    int64_t total_frames;
    double fps;
    int64_t dropped;
};

PerformanceMetrics::PerformanceMetrics(const uint64_t elapsed_us, const std::vector<int64_t> latency_us,
                                       const std::vector<int64_t> seq_ids) {
    avg_latency_ms = utils::avg(latency_us) / 1000.0;
    min_latency_ms = utils::min(latency_us) / 1000.0;
    max_latency_ms = utils::max(latency_us) / 1000.0;
    double elapsed_ms = static_cast<double>(elapsed_us / 1000.0);
    fps = latency_us.size() / elapsed_ms * 1000;

    dropped = 0;
    int64_t prev_seq_id = seq_ids[0];
    for (size_t i = 1; i < seq_ids.size(); ++i) {
        dropped += seq_ids[i] - prev_seq_id - 1;
        prev_seq_id = seq_ids[i];
    }
    total_frames = seq_ids.back() + 1;
}

std::ostream& operator<<(std::ostream& os, const PerformanceMetrics& metrics) {
    os << "throughput: " << metrics.fps << " FPS, latency: min: " << metrics.min_latency_ms
       << " ms, avg: " << metrics.avg_latency_ms << " ms, max: " << metrics.max_latency_ms
       << " ms, frames dropped: " << metrics.dropped << "/" << metrics.total_frames;
    return os;
}

namespace {

struct PerformanceStrategy : public BuildStrategy {
    explicit PerformanceStrategy(const bool _disable_copy): disable_copy(_disable_copy){};

    BuildStrategy::ConstructInfo build(const InferDesc& infer) override {
        std::vector<IDataProvider::Ptr> providers;
        const auto& input_data = infer.input_data;
        switch (input_data.index()) {
        case LayerVariantAttr<std::string>::index_of<cv::util::monostate>(): {
            LOG_INFO() << "Input data path for model: " << infer.tag
                       << " hasn't been provided. Will be generated randomly" << std::endl;
            providers = createRandomProviders(infer.input_layers, infer.generators);
            break;
        }
        case LayerVariantAttr<std::string>::index_of<std::string>(): {
            const std::filesystem::path path = cv::util::get<std::string>(input_data);
            if (std::filesystem::exists(path)) {
                LOG_INFO() << "Input data path: " << path << " for model: " << infer.tag
                           << " exists - data will be uploaded" << std::endl;
                auto layers_data = uploadData(path, infer.tag, infer.input_layers, LayersType::INPUT);
                providers = createConstantProviders(std::move(layers_data), extractLayerNames(infer.input_layers));
            } else {
                LOG_INFO() << "Input data path: " << path << " for model: " << infer.tag
                           << " provided but doesn't exist - will be generated randomly" << std::endl;
                providers = createRandomProviders(infer.input_layers, infer.generators);
            }
            break;
        }
        default:
            THROW_ERROR("Performance mode supports input data in form of either directory or single file!");
        }  // switch
        // NB: No special I/O meta for this mode
        std::vector<Meta> inputs_meta(infer.input_layers.size(), Meta{});
        std::vector<Meta> outputs_meta(infer.output_layers.size(), Meta{});
        return {providers, inputs_meta, outputs_meta, disable_copy};
    }

    bool disable_copy;
};

class SyncSimulation : public SyncCompiled {
public:
    struct Options {
        uint32_t after_iter_delay_in_us = 0u;
    };

    SyncSimulation(cv::GCompiled&& compiled, std::vector<DummySource::Ptr>&& sources, const size_t num_outputs,
                   const Options& options);

    Result run(ITermCriterion::Ptr criterion) override;

private:
    void reset();
    bool process(cv::GCompiled& pipeline);

    SyncExecutor m_exec;
    std::vector<DummySource::Ptr> m_sources;
    std::vector<cv::Mat> m_out_mats;
    int64_t m_ts, m_seq_id;

    std::vector<int64_t> m_per_iter_latency;
    std::vector<int64_t> m_per_iter_seq_ids;

    Options m_opts;
};

class PipelinedSimulation : public PipelinedCompiled {
public:
    PipelinedSimulation(cv::GStreamingCompiled&& compiled, std::vector<DummySource::Ptr>&& sources,
                        const size_t num_outputs);

    Result run(ITermCriterion::Ptr criterion) override;

private:
    bool process(cv::GStreamingCompiled& pipeline);

    PipelinedExecutor m_exec;
    std::vector<DummySource::Ptr> m_sources;
    cv::optional<int64_t> m_ts, m_seq_id;
    std::vector<cv::optional<cv::Mat>> m_opt_mats;

    std::vector<int64_t> m_per_iter_latency;
    std::vector<int64_t> m_per_iter_seq_ids;
};

//////////////////////////////// SyncSimulation ///////////////////////////////
SyncSimulation::SyncSimulation(cv::GCompiled&& compiled, std::vector<DummySource::Ptr>&& sources,
                               const size_t num_outputs, const SyncSimulation::Options& options)
        : m_exec(std::move(compiled)),
          m_sources(std::move(sources)),
          m_out_mats(num_outputs),
          m_ts(-1),
          m_seq_id(-1),
          m_opts(options) {
    LOG_DEBUG() << "Run warm-up iteration" << std::endl;
    this->run(std::make_shared<Iterations>(1u));
    LOG_DEBUG() << "Warm-up has finished successfully." << std::endl;
}

void SyncSimulation::reset() {
    for (auto src : m_sources) {
        src->reset();
    }
    m_exec.reset();
};

Result SyncSimulation::run(ITermCriterion::Ptr criterion) {
    using namespace std::placeholders;
    auto cb = std::bind(&SyncSimulation::process, this, _1);
    auto out = m_exec.runLoop(cb, criterion);
    PerformanceMetrics metrics(out.elapsed_us, m_per_iter_latency, m_per_iter_seq_ids);
    m_per_iter_latency.clear();
    m_per_iter_seq_ids.clear();
    std::stringstream ss;
    ss << metrics;
    this->reset();
    return Success{ss.str()};
};

bool SyncSimulation::process(cv::GCompiled& pipeline) {
    using ts_t = std::chrono::microseconds;
    auto pipeline_outputs = cv::gout();
    // NB: Reference is mandatory there since copying empty
    // Mat may lead to weird side effects.
    for (auto& out_mat : m_out_mats) {
        pipeline_outputs += cv::gout(out_mat);
    }
    pipeline_outputs += cv::gout(m_ts);
    pipeline_outputs += cv::gout(m_seq_id);

    cv::GRunArgs pipeline_inputs;
    pipeline_inputs.reserve(m_sources.size());
    for (auto src : m_sources) {
        cv::gapi::wip::Data data;
        src->pull(data);
        pipeline_inputs.push_back(std::move(data));
    }
    pipeline(std::move(pipeline_inputs), std::move(pipeline_outputs));
    const auto curr_ts = utils::timestamp<ts_t>();
    m_per_iter_latency.push_back(curr_ts - m_ts);
    m_per_iter_seq_ids.push_back(m_seq_id);

    // NB: Do extra busy wait to simulate the user's post processing after stream.
    if (m_opts.after_iter_delay_in_us != 0) {
        utils::busyWait(std::chrono::microseconds{m_opts.after_iter_delay_in_us});
    }
    return true;
}

//////////////////////////////// PipelinedSimulation ///////////////////////////////
PipelinedSimulation::PipelinedSimulation(cv::GStreamingCompiled&& compiled, std::vector<DummySource::Ptr>&& sources,
                                         const size_t num_outputs)
        : m_exec(std::move(compiled)), m_sources(std::move(sources)), m_opt_mats(num_outputs) {
    LOG_DEBUG() << "Run warm-up iteration" << std::endl;
    this->run(std::make_shared<Iterations>(1u));
    LOG_DEBUG() << "Warm-up has finished successfully." << std::endl;
}

Result PipelinedSimulation::run(ITermCriterion::Ptr criterion) {
    auto pipeline_inputs = cv::gin();
    for (auto source : m_sources) {
        pipeline_inputs += cv::gin(static_cast<cv::gapi::wip::IStreamSource::Ptr>(source));
    }

    using namespace std::placeholders;
    auto cb = std::bind(&PipelinedSimulation::process, this, _1);
    auto out = m_exec.runLoop(std::move(pipeline_inputs), cb, criterion);
    PerformanceMetrics metrics(out.elapsed_us, m_per_iter_latency, m_per_iter_seq_ids);
    m_per_iter_latency.clear();
    m_per_iter_seq_ids.clear();

    std::stringstream ss;
    ss << metrics;

    // NB: Reset sources since they may have their state changed.
    for (auto src : m_sources) {
        src->reset();
    }
    return Success{ss.str()};
};

bool PipelinedSimulation::process(cv::GStreamingCompiled& pipeline) {
    using ts_t = std::chrono::microseconds;
    cv::GOptRunArgsP pipeline_outputs;
    for (auto& opt_mat : m_opt_mats) {
        pipeline_outputs.emplace_back(cv::gout(opt_mat)[0]);
    }
    pipeline_outputs.emplace_back(cv::gout(m_ts)[0]);
    pipeline_outputs.emplace_back(cv::gout(m_seq_id)[0]);
    const bool has_data = pipeline.pull(std::move(pipeline_outputs));
    const auto curr_ts = utils::timestamp<ts_t>();
    ASSERT(m_ts.has_value());
    ASSERT(m_seq_id.has_value());
    m_per_iter_latency.push_back(curr_ts - *m_ts);
    m_per_iter_seq_ids.push_back(*m_seq_id);
    return has_data;
}

}  // anonymous namespace

PerformanceSimulation::PerformanceSimulation(ScenarioGraph&& graph, const PerformanceSimulation::Options& opts)
        : m_opts(opts),
          m_comp(Computation::build(std::move(graph), std::make_shared<PerformanceStrategy>(m_opts.inference_only),
                                    true)) {
}

std::shared_ptr<PipelinedCompiled> PerformanceSimulation::compilePipelined(const bool drop_frames,
                                                                           cv::GCompileArgs&& compile_args) {
    if (m_opts.inference_only) {
        compile_args += cv::compile_args(cv::gapi::wip::ov::benchmark_mode{});
    }
    auto info = m_comp.compilePipelined(drop_frames, std::move(compile_args));
    return std::make_shared<PipelinedSimulation>(std::move(info.compiled), std::move(info.sources),
                                                 info.out_meta.size());
}

std::shared_ptr<SyncCompiled> PerformanceSimulation::compileSync(const bool drop_frames,
                                                                 cv::GCompileArgs&& compile_args) {
    if (m_opts.inference_only) {
        compile_args += cv::compile_args(cv::gapi::wip::ov::benchmark_mode{});
    }
    auto info = m_comp.compileSync(drop_frames, std::move(compile_args));

    SyncSimulation::Options options{0u};
    if (m_opts.target_latency.has_value()) {
        if (!drop_frames) {
            THROW_ERROR("Target latency for the stream is only supported when frames drop is enabled!");
        }
        // NB: There is no way to specify more than one source currently so assert if it happened.
        ASSERT(info.sources.size() == 1u);
        const uint32_t target_latency_val = m_opts.target_latency.value();
        const uint32_t source_latency = info.sources.front()->getLatency();
        if (target_latency_val > source_latency) {
            THROW_ERROR("Target latency must be less or equal than source latency!");
        }
        options.after_iter_delay_in_us = (source_latency - target_latency_val) * 1000u;
    }
    return std::make_shared<SyncSimulation>(std::move(info.compiled), std::move(info.sources), info.out_meta.size(),
                                            options);
}
