/**
 * 内置源工厂 + 解析表 + 聚合构造（music 根目录基础设施）。
 * `MusicSourceFactory` 与内置表、`resolveBuiltinMusicSdk` 等同文件维护，供 `MusicSdkAggregate` 等调用；
 * 外层仍优先通过 `MusicFeatureEntry` 使用能力。
 */

import type { IMusicSource } from './sources/IMusicSource';
import type { SingleMusicSdkInterface, MusicSdkInterface } from './sources/MusicSdkContracts';
import { KuwoMusicSource } from './sources/kw/KuwoMusicSource';
import { KugouMusicSource } from './sources/kg/KugouMusicSource';
import { QQMusicSource } from './sources/tx/QQMusicSource';
import { NeteaseMusicSource } from './sources/wy/NeteaseMusicSource';
import { MiguMusicSource } from './sources/mg/MiguMusicSource';

export type BuiltinSourceId = 'kw' | 'kg' | 'tx' | 'wy' | 'mg';

interface BuiltinSdkTable {
  kw: SingleMusicSdkInterface;
  kg: SingleMusicSdkInterface;
  tx: SingleMusicSdkInterface;
  wy: SingleMusicSdkInterface;
  mg: SingleMusicSdkInterface;
}

const BUILTIN_ORDER: BuiltinSourceId[] = ['kw', 'kg', 'tx', 'wy', 'mg'];

export class MusicSourceFactory {
  private static singleton: MusicSourceFactory | undefined;
  private readonly instances: Map<string, IMusicSource> = new Map();

  static getInstance(): MusicSourceFactory {
    if (MusicSourceFactory.singleton === undefined) {
      MusicSourceFactory.singleton = new MusicSourceFactory();
    }
    return MusicSourceFactory.singleton;
  }

  /** 获取（或创建并缓存）指定源；首次创建后会触发异步 {@link IMusicSource#initialize} */
  getSource(sourceId: string): IMusicSource {
    let inst = this.instances.get(sourceId);
    if (inst === undefined) {
      inst = this.createSource(sourceId);
      this.instances.set(sourceId, inst);
      void inst.initialize();
    }
    return inst;
  }

  /** 直接拿到与历史兼容的扁平 SDK 对象 */
  getSdk(sourceId: string): SingleMusicSdkInterface {
    return this.getSource(sourceId).toSingleMusicSdkInterface();
  }

  getBuiltinIds(): BuiltinSourceId[] {
    return BUILTIN_ORDER.slice();
  }

  private createSource(sourceId: string): IMusicSource {
    if (sourceId === 'kw') {
      return new KuwoMusicSource();
    }
    if (sourceId === 'kg') {
      return new KugouMusicSource();
    }
    if (sourceId === 'tx') {
      return new QQMusicSource();
    }
    if (sourceId === 'wy') {
      return new NeteaseMusicSource();
    }
    if (sourceId === 'mg') {
      return new MiguMusicSource();
    }
    throw new Error(`Unknown music source: ${sourceId}`);
  }
}

const factory: MusicSourceFactory = MusicSourceFactory.getInstance();

const registryBuiltinOrder: BuiltinSourceId[] = factory.getBuiltinIds();

const builtinTable: BuiltinSdkTable = {
  kw: factory.getSdk('kw'),
  kg: factory.getSdk('kg'),
  tx: factory.getSdk('tx'),
  wy: factory.getSdk('wy'),
  mg: factory.getSdk('mg'),
};

export function resolveBuiltinMusicSdk(source: string): SingleMusicSdkInterface {
  if (source === 'kw') {
    return builtinTable.kw;
  }
  if (source === 'kg') {
    return builtinTable.kg;
  }
  if (source === 'tx') {
    return builtinTable.tx;
  }
  if (source === 'wy') {
    return builtinTable.wy;
  }
  if (source === 'mg') {
    return builtinTable.mg;
  }
  throw new Error(`Unknown or unsupported music source: ${source}`);
}

export function isBuiltinSourceId(id: string): boolean {
  return id === 'kw' || id === 'kg' || id === 'tx' || id === 'wy' || id === 'mg';
}


/** 与历史 `musicSdk` 对象形状一致，供直接点号访问 */
export function createMusicSdkAggregate(): MusicSdkInterface {
  const out: MusicSdkInterface = {
    kw: builtinTable.kw,
    kg: builtinTable.kg,
    tx: builtinTable.tx,
    wy: builtinTable.wy,
    mg: builtinTable.mg,
  };
  return out;
}

/** 获取工厂单例 */
export function getMusicSourceFactory(): MusicSourceFactory {
  return factory;
}
